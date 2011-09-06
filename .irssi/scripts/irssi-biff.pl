use Irssi;
use vars qw($VERSION %IRSSI); 
use File::Path qw(mkpath);

my $SKIP_MODE = 0;

$VERSION = "0.1";
%IRSSI =
(
    authors => "Ben Bernard and Keith Amling",
    contact => "bernard\@amazon.com",
    name    => "public / privmsg biff",
    description => "Custom (crummy) biffer",
    license => "None, Amazon internal",
    url     => "http://irssi.org/",
    changed => "2007-03-09",
    changes => ""
);

# Helper for debugging
sub print_msg
{
    Irssi::active_win()->print("@_");
}

sub msg_private
{
    my ($server, $msg, $nick, $address) = @_;

    #Exclude znc control queries
    return if ( $nick =~ m/^\*/ );

    biff("PRIVATE", $nick, $msg);
}

sub msg_public
{
    my ($server, $msg, $nick, $address, $channel) = @_;

    return if ( $channel eq '&bitlbee' );

    my $me = $server->{'nick'};
    if(defined($me) && $msg =~ /$me/)
    {
        biff("PRIVATE", "$channel:$nick", $msg);
    }
    else 
    {
        biff("PUBLIC", "$channel:$nick", $msg);
    }
}

sub join {
  my ($server, $channel, $nick, $address) = @_;

  if ( $channel eq '&bitlbee' ) {
    #biff('PUBLIC', "jabber join", "$nick joined jabber");
  }
}

sub quit {
  my ($server, $channel, $nick, $address, $reason) = @_;
  if ( $channel eq '&bitlbee' ) {
    #biff('PUBLIC', "jabber quit", "$nick left jabber: $reason");
  }
}

sub mode_change {
  # SERVER_REC, char *channel, char *nick, char *addr, char *mode
  my ($server, $channel, $setby, $address, $mode, $nick) = @_;

  if ( $channel eq '&bitlbee' ) {
    #biff('PUBLIC', "jabber mode", "$nick changed mode: $mode");
  }
}

sub biff {
  my $type    = shift || 'PUBLIC';
  my $from    = shift || 'none';
  my $message = shift || 'none';
  my $channel = shift;

  if ( $message =~ m/Buffer Playback.../ ) {
    $SKIP_MODE = 1;
    return;
  }

  if ( $message =~ m/Playback Complete/ ) {
    $SKIP_MODE = 0;
    return;
  }

  return if ( $SKIP_MODE );

  my $expire = 30;
  my $urgent = 0;

  if ( $type eq 'PRIVATE' ) {
    $expire = -1;
    $urgent = 1;
  }

  my $short_message = substr($message, 0, 20);

  my $subject = lc($type) . " message from $from: " . $short_message;

  my @args = (
    "--subject",     $subject, 
    "--expire-in",   $expire, 
    "--description", $message,
    "--program",     'irssi',
  );

  push @args, '--urgent' if ( $urgent );

  system("/home/benbernard/bin/createBiff", @args);
}

Irssi::signal_add('message private', 'msg_private');
Irssi::signal_add('message public', 'msg_public');
Irssi::signal_add('message join', 'join');
Irssi::signal_add('message quit', 'quit');
Irssi::signal_add('message irc mode', 'mode_change');
