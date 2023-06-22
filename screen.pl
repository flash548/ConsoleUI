use lib '.';
use Term::Console;
use Term::Window;
use Term::ReadKey;
use Time::HiRes qw/sleep/;
use Term::TransKeys;

binmode STDOUT, ":utf8";

my $console = Console->new(fill_char => "\x{2591}", fg=> 'red');
$console->init;

my $win = Window->new(console => $console, fill_char => '.', x => 0, y => 0, width => '50%', height => '25%', fg => 'red', bg => 'black', title=> "Win1");
my $win2 = Window->new(console => $console, fill_char => '.', x => 5, y => 5, width => '50%', height => '25%', fg => 'blue', bg => 'black', title=> "Win2");
$console->add_window($win, $win2);

$win->task(sub {
    for (1..10) {
        $win->write("$_\n");
        sleep 1;
    }
});

$win2->task(sub {
    for (1..10) {
        $win2->write("$_\n");
        sleep 1;
    }
});

my $listener = Term::TransKeys->new();
while ((my $key = $listener->TransKey) ne 'q') {    
    $console->dispatch_key($key);
}

END {
    $win->{task}->join if $win->{task};
    $win2->{task}->join if $win2->{task};
    $console->show_cursor;
}