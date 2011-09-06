# populates a window with the contents of the log for the query / channel
#
# 2 Settings:
#
# print_log_size - number of lines of log history to print, defaults to 25
# print_log_whole_log - ON | OFF, turn ON to ingore print_log_size and put the whole log in the window
#
# 1 Command:
# /printlog - prints the log right now normally not needed since the log is added when the channel is joined
#

use Irssi;
use Irssi::Irc;

#use warnings;
use strict;

# hmm... stolen..
# -verbatim- import expand
sub expand {
  my ($string, %format) = @_;
  my ($exp, $repl);
  $string =~ s/%$exp/$repl/g while (($exp, $repl) = each(%format));
  return $string;
}
# -verbatim- end

sub print_msg
{
    Irssi::active_win()->print("@_");
}

sub print_log_command {
  my ($data, $server, $witem) = @_;
  print_log($witem);
}

sub print_log_event {
  my ($window, $witem) = @_;
  print_log($witem);
}

sub print_log {
  my $witem = shift;
  return unless $witem;
  # $witem (window item) may be undef.

  my $name     = $witem->{'name'};
  my $chatnet  = $witem->{'server'}->{'chatnet'};
  my $log_file = "/home/bernard/.irclogs/$chatnet/$name.log";

  $log_file = "/home/bernard/.irclogs/$name.log" unless ( -e $log_file );

  if ( -e $log_file ) {
    my $log_size  = Irssi::settings_get_int("print_log_size");
    my $whole_log = Irssi::settings_get_bool("print_log_whole_log");

    my @lines;

    my $current_date = '';

    open ( my $command, '<', $log_file) or return;
    my $count = 0;
    while ( my $line = <$command> ) {
      chomp $line;
      $count++;

      if ( $line =~ m/^--- Log (?:opened|closed) (\S+) (\S+) (\S+) (\S+) (\S+)/ ) {
        $current_date = "$1 $2 $3 $5";
        next;
      }
      if ( $line =~ m/^--- Day changed (\S+) (\S+) (\S+) (\S+)/ ) {
        $current_date = "$1 $2 $3 $4";
      }

      push @lines, "$current_date $line";
    }

    close $command;

    my $last  = (scalar @lines) - 1;
    my $first = ($whole_log) ? 0 : ($last - $log_size);

    $witem->print($_, MSGLEVEL_CTCPS) for (@lines[$first .. $last]);
  }
}

Irssi::command_bind('printlog', 'print_log_command');
Irssi::signal_add_first('window item new', 'print_log_event');

Irssi::settings_add_int("populate_window", "print_log_size", 25);
Irssi::settings_add_bool("populate_window", "print_log_whole_log", 0);
