# Messages *status with ClearBuffer for the current query
#

use Irssi;
use Irssi::Irc;

#use warnings;
use strict;

sub print_msg
{
    Irssi::active_win()->print("@_");
}

sub clear_buffer_command {
  my ($data, $server, $witem) = @_;

  # $witem (window item) may be undef.
  return unless $witem;

  my $name     = $witem->{'name'};
  print_msg("Clearing: $name");
  $server->command("MSG *status ClearBuffer $name");
}

# sub print_log_event {
#   my ($window, $witem) = @_;
#   print_log($witem);
# }

# sub print_log {
#   my $witem = shift;

#   return unless $witem;
#   # $witem (window item) may be undef.

#   my $name     = $witem->{'name'};
#   my $chatnet  = $witem->{'server'}->{'chatnet'};
#   my $log_file = "$HOME_DIR/.irclogs/$chatnet/$name.log";

#   $log_file = "$HOME_DIR/.irclogs/$name.log" unless ( -e $log_file );

#   if ( -e $log_file ) {
#     my $log_size  = Irssi::settings_get_int("print_log_size");
#     my $whole_log = Irssi::settings_get_bool("print_log_whole_log");

#     my @lines;

#     my $current_date = '';

#     open ( my $command, '<', $log_file) or return;
#     my $count = 0;
#     while ( my $line = <$command> ) {
#       chomp $line;
#       $count++;

#       if ( $line =~ m/^--- Log (?:opened|closed) (\S+) (\S+) (\S+) (\S+) (\S+)/ ) {
#         $current_date = "$1 $2 $3 $5";
#         next;
#       }
#       if ( $line =~ m/^--- Day changed (\S+) (\S+) (\S+) (\S+)/ ) {
#         $current_date = "$1 $2 $3 $4";
#       }

#       push @lines, "$current_date $line";
#     }

#     close $command;

#     my $last  = (scalar @lines) - 1;
#     my $first = ($whole_log) ? 0 : ($last - $log_size);

#     $witem->print($_, MSGLEVEL_CTCPS) for (@lines[$first .. $last]);
#   }
# }

Irssi::command_bind('clearbuf', 'clear_buffer_command');
Irssi::command_bind('cb', 'clear_buffer_command');
