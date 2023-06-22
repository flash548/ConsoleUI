package Window;

use Term::ANSIColor;
use UUID::Tiny ':std';
use threads;

sub new {
    my $class = shift;
    my $self = {@_} || {};

    $self->{id} = create_uuid_as_string(UUID_V4);  # assign unique id

    $self->{console} = $self->{console} || die "No console handle given!";
    $self->{xpos} = 0;
    $self->{ypos} = 0;

    # parse X position - can be either a '%' string or coordinate number
    $self->{x} = do {
        if ($self->{x} && $self->{x} =~ /(\d+)\%/) {
            int(($1 / 100) * $self->{console}->{width});
        }
        elsif ($self->{x}) {
            $self->{x};
        }
        else {
            0;
        }
    };

    # parse Y position - can be either a '%' string or coordinate number
    $self->{y} = do {
        if ($self->{y} && $self->{y} =~ /(\d+)\%/) {
            int(($1 / 100) * $self->{console}->{height});
        }
        elsif ($self->{y}) {
            $self->{y};
        }
        else {
            0;
        }
    };

    # parse width - can be either a '%' string or scalar number
    $self->{width} = do {
        if ($self->{width} && $self->{width} =~ /(\d+)\%/) {
            int(($1 / 100) * $self->{console}->{width});
        }
        elsif ($self->{width}) {
            $self->{width};
        }
        else {
            10;
        }
    };

    # parse height - can be either a '%' string or scalar number
    $self->{height} =  do {
        if ($self->{height} && $self->{height} =~ /(\d+)\%/) {
            int(($1 / 100) * $self->{console}->{height});
        }
        elsif ($self->{height}) {
            $self->{height};
        }
        else {
            10;
        }
    };
    $self->{fill_char} = $self->{fill_char} || ' ';
    $self->{fg} = $self->{fg} || 'white';
    $self->{bg} = $self->{bg} || 'black';

    # the text content of this window
    $self->{buffer} = '';

    # optional title
    $self->{title} = $self->{title} || '';

    # actual coords to start writing window contents
    $self->{xpos} = $self->{x}+1;
    $self->{ypos} = $self->{y}+2;

    $self->{is_focused} = 0;
    return bless $self, $class;
}

sub draw {
    my $self = shift;

    my $border_color = do {
        if ($self->{is_focused}) {
            $self->{console}->{focused_color};
        }
        else {
            $self->{fg};
        }
    };

    # draw top bar/border of the window
    $self->{console}->write_xy(
            $self->{x}, 
            $self->{y},
             "+" . ('-' x ($self->{width} - 2)) . "+",
            fore => $border_color,
            back => $self->{bg},
            $self->{id},
    );

    # draw the title bar of the window with reversed colors
    $self->{console}->write_xy(
            $self->{x},
            $self->{y}+1,
            color($border_color) . "|" . color($self->{bg} . " on_" . $self->{fg}) . $self->{title} 
                . (' ' x ($self->{width} - length($self->{title}) - 2)) . color('reset') . color($border_color) . "|" . color('reset'),
            $self->{id},
    );

    # draw the left/right borders
    my $tmp_y = $self->{y}+2;
    for (0..($self->{height}-4)) {
        $self->{console}->write_xy(
                $self->{x},
                $tmp_y,
                '|',
                fore => $border_color,
                back => $self->{bg},
                $self->{id},
        );
        $self->{console}->write_xy(
                $self->{x} + ($self->{width}-1),
                $tmp_y,
                '|',
                fore => $border_color,
                back => $self->{bg},
                $self->{id},
        );
        $tmp_y++;
    }
    $self->{console}->write_xy(
            $self->{x},
            $tmp_y,
            "+" . ('-' x ($self->{width} - 2)) . "+",
            fore => $border_color,
            back => $self->{bg},
            $self->{id},
    );

    $self->reset_cursor;   
    $self->render_text; 
}

sub write {
    my $self = shift; 
    my $text = shift;
    $self->{buffer} .= $text;
    $self->render_text;
}

sub render_text {
    my $self = shift;
    $self->reset_cursor;
    my $tmp = '';
    my @lines = ();
    for my $char (split(//, $self->{buffer})) {
        if ($char eq "\n") { 
            push @lines, $tmp; 
            $tmp = ''; 
            next; 
        }
        else { 
            if (length($tmp) == (self->{$width}-2)) { 
                push @lines, $tmp; 
                $tmp = $char; 
                next; 
            } 
            else { 
                $tmp .= $char; 
            } 
        }
    }; 
    push (@lines, $tmp) if length($tmp) > 0; 

    my $start = ((@lines - ($self->{height}-3)) < 0) ? 0 : (@lines - ($self->{height}-3));

    # render the window's $buffer text
    for my $i ($start..(@lines-1)) {
        $self->{console}->write_xy(
            $self->{xpos},
            $self->{ypos},
            $lines[$i] . ($self->{fill_char} x (($self->{width}-2) - length($lines[$i]))),
            fore => $self->{fg},
            $self->{id}); 
        $self->{xpos} = $self->{x} + 1;
        $self->{ypos}++;
    }

    # fill any remaining space in the window with the fill_char
    while ($self->{ypos} <= $self->{y}+($self->{height}-2)) {
        $self->{console}->write_xy($self->{xpos}, 
            $self->{ypos}, 
            ($self->{fill_char} x ($self->{width}-2)), 
            fore => $self->{fg},
            $self->{id});
        $self->{xpos} = $self->{x} + 1;
        $self->{ypos}++;
    }
}

sub reset_cursor {
    my $self = shift;
    $self->{xpos} = $self->{x} + 1;
    $self->{ypos} = $self->{y} + 2;
}

sub task {
    my $self = shift;
    my $task = shift;
    $self->{task} = threads->create($task);    
}

# return true if given coordinate is in bounds of the window (including borders)
sub coord_in_bounds {
    my $self = shift;
    my $x = shift;
    my $y = shift;

    return ($self->{x} < $x && $x < $self->{x}+$self->{width}) &&
        ($self->{y} < $y && $y < $self->{y}+$self->{height});
}

sub process_key {

}

1;