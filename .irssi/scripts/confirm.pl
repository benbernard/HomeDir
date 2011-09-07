use Irssi;
use vars qw($VERSION %IRSSI); 

########### USAGE ###################
# put in .irssi/scripts (or .irssi/scripts/autorun to autouse it).
#
# Load with /script load confirm
# 
# You need to setup some config values:
# /set confirm_characters CHARS
# /set confirm_channels CHAN1:CHAN2:etc...
# 
# If any of the characters appear in the message text or if the channel / query
# is in the confirm_channels list (colon separated), then you will get a prompt
# to confirm.  type CNY to (CONFIRM-YES) to send the message.  You can also
# setup an ignore list to be able to paste in, for example, a block of code
# with /add_ignore_channel  and remove with /remove_ignore_channel see the list
# with /show_ignore_list and /show_confirm to redisplay the message that is
# waiting for confirmation (only one message is waiting at a time)
#

$VERSION = "0.1";
%IRSSI =
(
    authors => "Ben Bernard and Keith Amling",
    contact => "bernard\@amazon.com",
    name    => "public / privmsg biff",
    description => "confirm on channels and certain messages",
    license => "None",
    url     => "http://irssi.org/",
    changed => "2007-03-09",
    changes => ""
);

use Data::Dumper;

# Helper for debugging
sub print_msg
{
    Irssi::active_win()->print(join('', Data::Dumper->Dump([@_])));
}

my $IGNORE_LIST = {};
my $WAITING_CONFIRMS = {};

sub add_confirm {
  my $line  = shift;
  my $witem = shift;

  my $name = $witem->{'name'};
  $WAITING_CONFIRMS->{$name} = $line;

  my $length = length($line);

  Irssi::active_win()->print("Please confirm sending message:\n$line\nEnter CNY to confirm sending this message, letter count: $length");
}

sub check_confirm {
  my $line   = shift;
  my $server = shift;
  my $witem  = shift;

  my $name = $witem->{'name'};
  if ( uc($line) eq 'CNY' ) {
    if ( $WAITING_CONFIRMS->{$name} ) {
      my $message = $WAITING_CONFIRMS->{$name};
      $server->command("MSG $name $message");
      delete $WAITING_CONFIRMS->{$name};
    }
  }
}

sub send_text {
  my ($line, $server, $witem) = @_;

  if ( check_for_stop($line, $server, $witem) ) {
    Irssi::signal_stop();
  }
}

sub fix_colon_special_cases {
  my $line  = shift;
  my $witem = shift;

  #use Data::Dumper; warn Dumper $witem->nicks();

  #remove smilies :), :(, :P, :D
  $line =~ s/\:[()PD8p](\s|$)//g;

  my @nicks = ();
  #remove nick:
  if ( $witem ) {
    if ( $witem->isa('Irssi::Irc::Channel') ) {
      @nicks = map { $_->{'nick'} } $witem->nicks();
    }
    elsif ( $witem->isa('Irssi::Irc::Query') ) {
      push @nicks, $witem->{'name'};
    }
  }

  foreach my $nick (@nicks) {
    $line =~ s/$nick://ig;
  }

  $line =~ s/https?:\/\/\S+//g;
  
  return $line;
}

sub check_for_stop {
  my ($line, $server, $witem) = @_;

  my $changed_line = fix_colon_special_cases($line, $witem);

  my $characters = Irssi::settings_get_str("confirm_characters");

  my $regex = "^[^$characters].*[$characters]";

  return 0 if ( $IGNORE_LIST->{$witem->{'name'}} );
  return 1 if ( check_confirm($line, $server, $witem) );

  if ( $characters && ($changed_line =~ m/$regex/ || $changed_line =~ m/(^|[^0-9])[0-9]{6}([^0-9]|$)/ ) ) {
    add_confirm($line, $witem);
    return 1;
  }
  else {
    my $type = $witem->{'type'};
    my $channels = [split(':', Irssi::settings_get_str("confirm_channels"))];
    if ( $type eq 'CHANNEL' || $type eq 'QUERY' ) {
      my $name = $witem->{'name'};
      if ( grep { $name =~ m/^\#?$_$/ } @$channels ) {
        add_confirm($line, $witem);
        return 1;
      }
    }
  }

  return 0;
}

sub show_confirm {
  my ($line, $server, $witem) = @_;
  if ( my $message = $WAITING_CONFIRMS->{$witem->{'name'}} ) {
    Irssi::active_win()->print("Waiting to confirm: $message");
  }
}

sub add_ignore_channel {
  my ($line, $server, $witem) = @_;
  my $name = $witem->{'name'};

  if ( ! $IGNORE_LIST->{$name} ) {
    $IGNORE_LIST->{$name} = 1;
    Irssi::active_win()->print("Added ignore list item: $name");
  }
}

sub remove_ignore_channel {
  my ($line, $server, $witem) = @_;
  my $name = $witem->{'name'};

  delete $IGNORE_LIST->{$name};
  Irssi::active_win()->print("Removed ignore list item: $name");
}

sub show_ignore_list {
  my $list = join(' ', keys %$IGNORE_LIST);
  Irssi::active_win()->print("Ignore Channels List: $list");
}

Irssi::signal_add('send text', \&send_text);
Irssi::command_bind('show_confirm', 'show_confirm');
Irssi::command_bind('add_ignore_channel', 'add_ignore_channel');
Irssi::command_bind('remove_ignore_channel', 'remove_ignore_channel');
Irssi::command_bind('show_ignore_list', 'show_ignore_list');
Irssi::settings_add_str("confirm", "confirm_channels", ''); 
Irssi::settings_add_str("confirm", "confirm_characters", ''); 
