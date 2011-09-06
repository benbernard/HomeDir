use strict;
use vars qw($VERSION %IRSSI);

$VERSION = '0.4';
%IRSSI = (
    authors     => 'Tijmen "timing" Ruizendaal',
    contact     => 'tijmen.ruizendaal@gmail.com',
    name        => 'bitlbee_blist',
    description => '/blist <all|online|offline|away> <word>,  greps <word> from blist for bitlbee',
    license     => 'GPLv2',
    url         => 'http://the-timing.nl/stuff/irssi-bitlbee',
    changed     => '2006-10-27',
);

my $bitlbee_server_tag = "localhost";
my $bitlbee_channel = "&bitlbee";
my $bitlbee_server;
my ($list, $word);

get_channel();

Irssi::signal_add_last 'channel sync' => sub {
        my( $channel ) = @_;
        if( $channel->{topic} eq "Welcome to the control channel. Type \x02help\x02 for help information." ){
                $bitlbee_server_tag = $channel->{server}->{tag};
                $bitlbee_server = $channel->{server};
                $bitlbee_channel = $channel->{name};
        }
};

sub get_channel {
        my @channels = Irssi::channels();
        foreach my $channel(@channels) {
                if ($channel->{topic} eq "Welcome to the control channel. Type \x02help\x02 for help information.") {
                        $bitlbee_channel = $channel->{name};
                        $bitlbee_server_tag = $channel->{server}->{tag};
                        $bitlbee_server = $channel->{server};
                        return 1;
                }
        }
        return 0;
}

sub print_msg {
    Irssi::active_win()->print("@_");
}

sub blist {
  my ($args, $server, $winit) = @_;
  print_msg("got args: $args");
  ($list, $word) = split(/ /, $args);

  if ( ! grep { $list eq $_ } qw(all online offline away)) {
    my $temp = $word;
    $word = $list;
    $word .= " $temp" if ($temp);
    $list = 'all';
  }

  print_msg("list: $list word: $word");

  get_channel();

  if ( $bitlbee_server ) {
    $bitlbee_server->command("msg $bitlbee_channel blist $list");
    Irssi::signal_add('event privmsg', 'grep');  
  }
  else {
    print_msg("Ack! No bitlbee server found!");
  }
}

sub grep {
  my ($server, $data, $nick, $address) = @_;
  my ($target, $text) = split(/ :/, $data, 2);
  if ($text =~ /$word/ && $target =~ /$bitlbee_channel/){
    print_msg($text);
    Irssi::signal_stop();
  } else {Irssi::signal_stop();}
  if ($text =~ /buddies/ && $target =~/$bitlbee_channel/){Irssi::signal_remove('event privmsg', 'grep');} 
}

Irssi::command_bind('blist','blist');
