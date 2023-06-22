package Console;

use Term::ANSIColor;
use threads ('yield',
            'stack_size' => 64*4096,
            'exit' => 'threads_only',
            'stringify');
use threads::shared;

sub new {
    my $class = shift;
    my $self = {@_} || {};
    my ($rows, $cols) = `stty size` =~ m/(\d+)\s+(\d+)/;
    my $scrn_lock :shared;
    $self->{rows} = $rows;
    $self->{cols} = $cols;
    $self->{width} = $cols-1;
    $self->{height} = $rows-1;
    $self->{fill_char} = $self->{fill_char} || ' ';
    $self->{fg} = $self->{fg} || 'white';
    $self->{bg} = $self->{bg} || 'black';
    $self->{lock} = \$scrn_lock;
    $self->{active_window} = undef;
    $self->{active_window_idx} = undef;
    $self->{windows} = [];
    $self->{focused_color} = $self->{focused_color} || 'cyan';
    # $self->{vcons} = [];
    return bless $self, $class;
}

sub init {
    my $self = shift;
    $self->hide_cursor;
    $self->clear;
    #$self->init_vcons;
}

# build out the virtual console in memory rows x cols
# sub vcons {
#     my $self = shift;
#     for (0..$self->{rows}-1) {
#         my $blank_row = [];
#         for (0..$self->{cols}-1) {
#             push @{$blank_row}, ' ';
#         }
#         push @{$self->{vcons}}, $blank_row;
#     }
# }

sub redraw {
    my $self = shift;
    for (@{$self->{windows}}) {
        $_->draw;
    }
}

# physically move the cursor on the console to x,y
sub move_cursor {
    my $self = shift;
    my $x = shift;
    my $y = shift;
    sprintf "\033[%d;%dH", $y+1, $x+1;
}

sub write_xy {
    my $self = shift;
{
        lock($self->{lock});
        my $x = shift;
        my $y = shift;
        my $str = shift;
        my $window_id = shift;
        my %colors = @_;
        my $ctrl = $self->move_cursor($x, $y);
        $ctrl .= $colors{fore} ? color($colors{fore}) : '';
        $ctrl .= $str;
        $ctrl .= color('reset');
        print $ctrl . "\n" unless $self->_clear_to_write($x, $y);
    }
}

sub fill {
    my $self = shift;

    {
        lock($self->{lock});
        my %args = @_;
        for ($args{y}..($args{y}+$args{height}-1)) {
            $self->write_xy($args{x}, $_, $args{char} x $args{width},
                fore => $args{fore}, back => $args{back});
        }
    }

}

sub clear {
    my $self = shift;
    $self->fill(x => 0, y => 0,
        width => $self->{width}, height => $self->{height},
        char => $self->{fill_char}, fore => $self->{fg},
        back => $self->{bg});
}

sub hide_cursor {
    print "\e[?25l";
}

sub show_cursor {
    print "\e[0H\e[0J\e[?25h";
}

sub add_window {
    my $self = shift;
    for my $win (@_) {
        push @{$self->{windows}}, $win;
        $win->draw;
    }
    
    # set focus to last window added
    $self->{active_window_idx} = $#{$self->{windows}};    
    $self->focus_active_window;
}

sub _clear_to_write {
    my $self = shift;
    my $window_id = shift;
    my $x = shift;
    my $y = shift;

    # true if no one owns this coordinate
    return 1 if !defined($window_id);

    # true if owning window id eq window_id
    # false if not equal
    return $self->_coord_owner($x, $y) eq $window_id;
}

# who (which window id) owns given coordinate
# upon multiple matches, then take the window that has focus
sub _coord_owner {
    my $self = shift;
    my $x = shift;
    my $y = shift;

    my @owners;
    for my $win (@{$self->{windows}}) {
        if ($win->coord_in_bounds($x, $y)) {
            push @owners, $win;
        }
    }

    for my $owner (@owners) {
        if ($owner->{is_focused}) {
            return $owner->{id};
        }
    }

    return undef;  # no window owns/overlaps with coordinate
}

sub focus_active_window {
    my $self = shift;

    return unless defined $self->{active_window_idx};

    # remove all focuses...
    for my $win (@{$self->{windows}}) {
        $win->{is_focused} = 0;
        $win->draw;
    }

    # reapply the focus to the active window
    $self->{active_window} = $self->{windows}->[$self->{active_window_idx}];
    $self->{active_window}->{is_focused} = 1;
    $self->{active_window}->draw;

}

sub move_window_focus {
    my $self = shift;
    my $dir = shift;

    return unless defined $self->{active_window_idx};

    if ($dir eq "left") {

        # check for wrapping
        if ($self->{active_window_idx}-1 < 0) {
            $self->{active_window_idx} = $#{$self->{windows}};
        }
        else {
            $self->{active_window_idx}--;
        }
    }
    elsif ($dir eq "right") {
        # check for wrapping
        if ($self->{active_window_idx}+1 > $#{$self->{windows}}) {
            $self->{active_window_idx} = 0;
        }
        else {
            $self->{active_window_idx}++;
        }
    }

    # reapply the focus
    $self->focus_active_window;
}

# handle key press event to focused window or the application
sub dispatch_key {
    my $self = shift;
    my $key = shift;
    return unless defined $self->{active_window_idx};
    
    if ($key eq "<LEFT>") {
        $self->move_window_focus("left");
    }
    elsif ($key eq "<RIGHT>") {
        $self->move_window_focus("right");
    }
    else {
        # pass it off to the active window
        $self->{active_window}->process_key($key) if defined($self->{active_window});
    }
}


1;
