#{{{ POD
=pod

=head1 NAME

    Term::TransKeys - Methods to read input while responding to special keys

=head1 DESCRIPTION

    Provides methods for reading text input while responding to special keys.

     * Bind functionality to any key
     * Read STDIN for input
     * Input is preserved if a bound key is pressed during input.
     * Bound key functionality can manipulate the input buffer in real time
     * Bound key functionality runs when key is pressed, does not wait for input to be completely entered.

=head1 SYNOPSIS

    use Term::TransKeys;

    my $listener = Term::TransKeys->new(
        actions => {
            '<F1>' => sub {
                ... Do something when the F1 key is pressed
            }
        }
    );

    # Term::Screen is not a requirement, just used in example.
    use Term::Screen;
    my $scr = new Term::Screen;

    $scr->clrscr;
    while ( 1 ) {
        # Place to hold the line of input
        my $line;

        # print the buffer until we have a complete line of input, non-blocking IO, loop at 0.01 interval.
        while ( not defined ($line = $listener->ActionRead( mode => 0.01 ))) {

            # Lets provide a prompt
            my $prompt = "input: ";

            # Print our current position (from right) in the buffer.
            $scr->at( 15, 0 )->clreol->puts( $listener->BufferPosition );
            # Show the prompt as well as the text entered so far.
            $scr->at(10,0)->clreol->puts( "input: " . $listener->BufferString );
            # Move the cursor to the currect position in the text
            $scr->at( 10, $listener->BufferPosition + length( $prompt ));
        }

        # When we have a new completed line:
        #  * Delete the line at the top of the screen, moving other lines up.
        #  * Output the new line at row 9.
        chomp( $line );
        $scr->at(0,0)->dl;
        $scr->at(9,0)->clreol->puts( $line );
        exit(0) if $line eq 'exit';
    }

=cut
#}}}

package Term::TransKeys;
use strict;
use warnings;
use Term::ReadKey;

use vars qw($VERSION $KEYMAP);

$VERSION = '1.01';

#{{{ Keys POD

=head1 Recognised Keys:

      Key           Default actions when using ActionRead(). These may be
                    overriden in new, or in the method call.
-------------------------------------------------------------------------
    <ESCAPE>        - Clear the buffer
    <ENTER>         - Insert a newline into the buffer unless <ENTER> is the end character
    <BACKSPACE>     - delete the character at the cursor

    -------- Function Keys
    <F1>
    <F2>
    <F3>
    <F4>
    <F5>
    <F6>
    <F7>
    <F8>
    <F9>
    <F10>
    <F11>
    <F12>

    -------- Arrow Keys
    <UP>            - Buffer history, previous line of input
    <DOWN>          - Buffer history, next line of input
    <RIGHT>         - Move cursor position right
    <LEFT>          - Move the cursor position left

    -------- I do not know what to call this group
    <INSERT>
    <HOME>          - Move cursor to start of buffer
    <DELETE>        - Delete the character after the cursor position
    <END>           - Move curstor to end of buffer
    <PAGE UP>
    <PAGE DOWN>
        <CONTEXT>       # Note: This is the menu key usually next to the windows key.

    -------- Control Keys
    <CONTROL+[A-Z]> # Note: control+j and control+m both map to <ENTER>
        <CONTROL+C> - exit(0)
        <CONTROL+D> - Finished entering input
        <CONTROL+Z> - Same as at shell, stop the process.

    -------- Regular keys
    |Any Text key|  - adds that key to the current position in the buffer

    TransKey() will act like readkey, except when one of the above keys is
    pressed, in these cases it will return the string listed above under 'key'

=cut

#}}}
#{{{ Keymaps
my $ALPHA = [ 'A' .. 'Z' ];
$KEYMAP = {
    '27' => '<ESCAPE>',
    '27-79-80' => '<F1>',
    '27-79-81' => '<F2>',
    '27-79-82' => '<F3>',
    '27-79-83' => '<F4>',
    '27-91-49-53-126' => '<F5>',
    '27-91-49-55-126' => '<F6>',
    '27-91-49-56-126' => '<F7>',
    '27-91-49-57-126' => '<F8>',
    '27-91-50-48-126' => '<F9>',
    '27-91-50-49-126' => '<F10>',
    '27-91-50-51-126' => '<F11>',
    '27-91-50-52-126' => '<F12>',
    '27-91-50-126' => '<INSERT>',
    '27-91-49-126' => '<HOME>',
    '27-91-51-126' => '<DELETE>',
    '27-91-52-126' => '<END>',
    '27-91-53-126' => '<PAGE UP>',
    '27-91-54-126' => '<PAGE DOWN>',
    '27-91-65' => '<UP>',
    '27-91-66' => '<DOWN>',
    '27-91-67' => '<RIGHT>',
    '27-91-68' => '<LEFT>',
    '27-91-50-57-126' => '<CONTEXT>',
    (map { $_ => '<CONTROL+' . $ALPHA->[$_ - 1] . '>' } 1 .. 26),
    '10' => '<ENTER>',
    '13' => '<ENTER>',
    '127' => '<BACKSPACE>',
};
#}}}

=head1 Constructors and Accessor Methods

=over 4

=cut

#{{{ Constructors and Accessors

=item new()

    Create a new TransKey object. Each object maintains it's own buffer, and
    has its own bound functionality.

    my $listener = Term::TransKeys->new(
        history_length => 20, #Default is 20, how much history to keep.
        history => [
            'A Line',
            "Another line",
            "so on...",
        ],
        # Actions are only used by ActionRead not TransKey.
        actions => {
            '<F1>' => sub { #Do something when F1 is pressed },
            'a' => sub { #do something when 'a' is pressed, as well as adding it to the buffer },
            '<CONTROL+Z>' => sub { #override control+z behavior },
        }
    );

=cut

sub new {
    my $class = shift;
    $class = ref $class || $class;

    my %params = @_;

    return bless {
        buffer => [],
        history_length => 20,
        history => [],
        %params, #This before actions, we want to add to actions, not take their place.
        actions => {
            '<BACKSPACE>' => \&ActionBS,
            '<ESCAPE>' => \&ActionEsc,
            '<CONTROL+C>' => \&ActionCC,
            '<CONTROL+D>' => \&ActionCD,
            '<CONTROL+Z>' => \&ActionCZ,
            '<UP>' => \&ActionUp,
            '<DOWN>' => \&ActionDown,
            '<RIGHT>' => \&ActionRight,
            '<LEFT>' => \&ActionLeft,
            '<HOME>' => \&ActionHome,
            '<END>' => \&ActionEnd,
            '<DELETE>' => \&ActionDel,
            '<ENTER>' => \&ActionEnter,
            %{ $params{ actions } || {}}, #Merge in specified actions.
        },
    }, $class;
}

=item Actions()

    Get the hash of key => action bindings.

    you can override an action like so:
    $listener->Actions->{ '<ESCAPE>' } = sub { ... };

=cut

sub Actions {
    my $self = shift;
    return $self->{ actions };
}

#}}}

=back

=head1 Buffer Methods

=over 4

=cut

#{{{ Buffer Methods

sub _PushBuffer {
    my $self = shift;
    push @{ $self->_GetBuffer } => @_;
}

sub _ShiftBuffer {
    my $self = shift;
    return if $self->BufferEmpty;
    my $key = shift( @{ $self->_GetBuffer });
    $key = $KEYMAP->{ ord($key) } || $key;
    return $key;
}

sub _GetBuffer {
    my $self = shift;
    return $self->{ buffer };
}

sub _ResetBuffer {
    my $self = shift;
    $self->{ buffer } = [];
    delete $self->{ _buff_pos_inv };
    delete $self->{ _buff_pos };
    return 1;
}

sub _BufferPosition {
    my $self = shift;
    my ( $diff, $buff ) = @_;
    unless( defined $diff ) {
        return $self->{ _buff_pos_inv } || 0;
    }
    my $min = 0;
    my $max = @$buff || 0;
    my $old = $self->{ _buff_pos } || 0;

    my $idx = $old + ($diff || 0);

    if (( my $off = $idx - $max ) > 0) {
        $idx -= $off;
    }
    if (( my $off = $min - $idx ) > 0) {
        $idx += $off;
    }

    $self->{ _buff_pos } = $idx;
    $self->{ _buff_pos_inv } = $max - $idx;
    return $self->{ _buff_pos_inv };
}

=item BufferPosition()

    Get the current cursor position in the buffer. (Where the next character
    will be inserted). 0 means before the first character, 1 means before the
    second character.

=cut

sub BufferPosition {
    my $self = shift;
    return $self->_BufferPosition( undef, undef );
}

=item BufferEmpty()

    Returns true if the buffer is empty.

=cut

sub BufferEmpty {
    my $self = shift;
    return not @{ $self->_GetBuffer };
}

=item BufferString()

    Returns the contents of the buffer as a concatenated string.

=cut

sub BufferString {
    my $self = shift;
    return join( '', @{ $self->_GetBuffer } );
}

#}}}

=back

=head1 Input Methods

=over 4

=cut

#{{{ Input Methods

=item TransKey()

    Get a single input key.

    Acts like ReadKey, except that when a special key is pressed it will return '<KEY>'

    Takes one optional parameter, mode. -1 is non-blocking, 0 is blocking,
    $mode > 0 is timed. Default is 0.

    return undef if no input is recieved in non-blocking mode or before timeout.

=cut

sub TransKey {
    my $self = shift;
    my ( $mode ) = @_;
    $mode ||= 0;
    return $self->_ShiftBuffer unless $self->BufferEmpty;

    ReadMode 4;

    my @keys;
    my $key;
    return undef unless defined ($key = ReadKey($mode));
    push @keys => $key;
    if ( ord( $key ) == 27 ) {
        while ( defined ($key = ReadKey(-1))) {
            push @keys => $key;
        }
    }

    ReadMode 0;

    #If there is only 1 key return it.
    if ( @keys == 1 ) {
        my $key = $KEYMAP->{ ord($keys[0]) } || $keys[0];
        return $key;
    }

    #If we have multiple keys check for a recognised sequence
    my $sequence = join('-', map { ord($_) } @keys );
    if( $key = $KEYMAP->{ $sequence } ) {
        return $key;
    }

    #If we have multiple keys that don't make a known sequence return them one at a time.
    $self->_PushBuffer( @keys );
    return $self->_ShiftBuffer;
}

=item ActionRead()

    Obtain a line of input. Line is used liberally, if 'end' parameter is
    specifed the 'line' may contain multiple lines.

    Parameters:

    $listener->ActionRead(
        actions => {
            <F1> => sub { ... }, #Action to run when F1 is pressed.
            ...
            # Actions overriden here remain overriden only for this method
            # call. Next method call they will be restored.
            # In order to override permanently override in the constructor, or
            # using the Actions() accessor.
        },
        mode => 0, #Default is 0, -1 is non-blocking, 0 is blocking, >0 is timed.
        end => '<ENTER>', #Return the line when this key is pressed.
            # You can use any printable character, or recognised ('<KEY>') key
            # here. Default is '<ENTER>'
            # Use something like '__TERM__' to force it to only return once
            # control+d has been pressed. *** NOTE: Do not override control+d if
            # you specify something other than a key here!. ***
    );

=cut

sub ActionRead {
    my $self = shift;
    my %params = @_;
    my $actions = {
        %{ $self->Actions },
        %{ $params{ actions } || {}},
    };
    my $mode = $params{ mode } || 0;
    my $endchar = $params{ end } || '<ENTER>';

    my @keys;
    my $key = '';
    while ( $key ne $endchar ) {
        my $seen = not $self->BufferEmpty;
        unless( $key = $self->TransKey( $mode )) {
            $self->_PushBuffer( @keys );
            $self->_BufferPosition( 0, \@keys );
            return undef;
        }

        if ( length($key) == 1 ) {
            if ( $seen ) {
                push @keys => $key;
            }
            else {
                no warnings;
                my $pos = $self->_BufferPosition( 0, \@keys );
                splice @keys, $pos, 0, $key;
                $self->_BufferPosition( 0, \@keys );
            }
        }
        $actions->{ $key }->( $self, \@keys, $endchar, \$key ) if exists $actions->{ $key };
    }
    $self->_ResetBuffer;
    $self->_ClearHistBuff;
    return unless @keys;
    $self->AddHistory([ @keys ]);
    return join( '', @keys );
}
#}}}

=back

=head1 Action Methods

    I consider these methods because the first parameter should be the listener,
    however they can just as easily be considered functions as they are called w/
    the listener as a parameter and not as $listener->Action() in most cases.

=over 4

=cut

#{{{ Action Methods

=item ActionBS()

    <BACKSPACE> default action.

=cut

sub ActionBS {
    my $self = shift;
    my ( $keys, $endchar ) = @_;
    my $pos = $self->_BufferPosition( 0, $keys ) - 1;
    my $char = $pos < 0 ? undef : $keys->[ $pos ];
    return if $pos < 0;
    return splice @$keys, $pos, 1;
}

=item ActionEsc()

    <ESCAPE> default action.

=cut

sub ActionEsc {
    my $self = shift;
    my ( $keys, $endchar ) = @_;
    @$keys = ( $endchar );
}

=item ActionCC()

    <CONTROL+C> default action.

=cut

sub ActionCC {
    print "\n";
    exit(0);
}

=item ActionCD()

    <CONTROL+D> default action.

=cut

sub ActionCD {
    my $self = shift;
    my ( $keys, $endchar, $key ) = @_;
    $$key = $endchar;
}

=item ActionCZ()

    <CONTROL+Z> default action.

=cut

sub ActionCZ {
    system( "kill -STOP $$" );
}

=item ActionUp()

    <UP> default action.

=cut

sub ActionUp {
    my $self = shift;
    my ( $keys, $endchar ) = @_;

    my $hist = $self->_GetHistBuff;

    my $idx = $self->_HistPos(0);
    @{ $hist->[ $idx ]} = @$keys;

    $idx = $self->_HistPos(1);
    @$keys = @{ $hist->[ $idx ]};
    $self->ActionEnd( $keys );
}

=item ActionDown()

    <DOWN> default action.

=cut

sub ActionDown {
    my $self = shift;
    my ( $keys, $endchar ) = @_;

    my $hist = $self->_GetHistBuff;

    my $idx = $self->_HistPos(0);
    @{ $hist->[ $idx ]} = @$keys;

    $idx = $self->_HistPos(-1);
    @$keys = @{ $hist->[ $idx ]};
    $self->ActionEnd( $keys );
}

=item ActionLeft()

    <LEFT> default action.

=cut

sub ActionLeft {
    my $self = shift;
    my ( $keys, $end ) = @_;
    $self->_BufferPosition( 1, $keys );
}

=item ActionRight()

    <RIGHT> default action.

=cut

sub ActionRight {
    my $self = shift;
    my ( $keys, $end ) = @_;
    $self->_BufferPosition( -1, $keys );
}

=item ActionHome()

    <HOME> default action.

=cut

sub ActionHome {
    my $self = shift;
    my ( $keys, $end ) = @_;
    return $self->_BufferPosition( 0 + @$keys, $keys ) eq 0;
}

=item ActionEnd()

    <END> default action.

=cut

sub ActionEnd {
    my $self = shift;
    my ( $keys, $end ) = @_;
    return $self->_BufferPosition( 0 - @$keys, $keys ) eq @$keys;
}

=item ActionDel()

    <DELETE> default action.

=cut

sub ActionDel {
    no warnings;
    my $self = shift;
    my ( $keys, $end ) = @_;
    my $pos = $self->_BufferPosition;
    if ( my $char = $keys->[ $pos ] ) {
        splice @$keys, $pos, 1;
        $self->_BufferPosition( -1, $keys );
        return $char;
    }
    return undef;
}

=item ActionEnter()

    <ENTER> default action.

=cut

sub ActionEnter {
    no warnings;
    my $self = shift;
    my ( $keys, $end, $key ) = @_;
    return 1 if ( $end eq $$key );
    my $pos = $self->_BufferPosition( 0, $keys );
    splice @$keys, $pos, 0, "\n";
    return $keys->[$pos] eq "\n";
}

#}}}

=back

=head1 Creating your own action

    sub MyAction {
        # Get the Term::TransKeys object
        my $listener = shift;
        # Get a reference to the current array of keys, and the character used
        # to return the lien of input.
        my ( $keys, $endchar, $key ) = @_;

        # Add a character to the end of the key array
        push( @$keys, 'a' );
        # Change the key recieved from what it was to the end character forcing
        # the input to return
        $key is a scalar reference.
        $$key = $endchar;
    }

=over 4

=item Note

    You can modify the @$keys array in any way you want, but remember it is a reference:
    $keys = [ qw/ a b c /]; # Will do nothing useful, in fact we loose the
                            # ability to modify the input buffer.
    @$keys = ( qw/ a b c /); # use this instead, modify the correct array.

=item Now to use the action

    my $line = $listener->ActionRead(
        actions => {
            '<CONTROL+D>' => \&MyAction,
        },
        end => '__TERM__', #Input only ends when control+d is pressed.
    );

=back

=head1 History Methods

=over 4

=cut

#{{{ History Methods
sub _GetHistBuff {
    my $self = shift;

    unless( $self->{ _HistBuff } ){
        $self->{ _HistBuff } = [
            [ @{ $self->_GetBuffer }],
            map { [ @$_ ] } @{ $self->GetHistory },
        ];
    }

    return $self->{ _HistBuff };
}

sub _HistPos {
    my $self = shift;
    my ( $diff ) = @_;
    my $idx = ($self->{ __HistPos } || 0) + ($diff || 0);

    $idx-- while( $idx >= ( @{ $self->_GetHistBuff } || 1 ));
    $idx++ while( $idx < 0 );

    $self->{ __HistPos } = $idx;
    return $idx;
}

sub _ClearHistBuff {
    my $self = shift;
    delete $self->{ _HistBuff };
    delete $self->{ __HistPos };
    return not ( $self->{ _HistBuff } or $self->{ __HistPos });
}

=item GetHistory()

    Returns an arrayref to the history array.
    Modifying the arrayref will bypass history_length. However the length will
    be enforced again as sson as AddHistory() is called.

=cut

sub GetHistory {
    my $self = shift;
    return $self->{ history };
}

=item AddHistory()

    Add item(s) to history. Use this instead of modifying the array from
    GetHistory, this method enforces history_length.

=cut

sub AddHistory {
    my $self = shift;
    $self->{ history } ||= [];
    my $history = $self->GetHistory;

    unshift @$history => @_;
    pop( @$history ) while @$history > $self->HistoryLength;
    return 1;
}

=item HistoryLength()

    Get/Set the length of the history.

=cut

sub HistoryLength {
    my $self = shift;
    my ( $new ) = @_;
    $self->{ history_length } = $new if defined $new;
    $self->{ history_length } = 1 unless $self->{ history_length } and $self->{ history_length } > 0;
    return $self->{ history_length } || 1;
}
#}}}

END {
    ReadMode 0;
}

=head1 AUTHOR

Chad Granum E<lt>exodist7@gmail.comE<gt>

=head1 COPYRIGHT

Copyright 2008 Chad Granum

You should have received a copy of the GNU General Public License
along with this.  If not, see <http://www.gnu.org/licenses/>.

=cut
