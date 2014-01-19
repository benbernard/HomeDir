#!/usr/bin/perl -w

use strict;

$ENV{'SCREENDIR'} = '/Users/bernard/.screen';
my $temp_file = '/tmp/buffer-exchange';
my $current_contents = get_clip();

while(1) {
  my $new = get_clip();
  if ( $current_contents eq $new ) {
    sleep 1;
    next;
  }
  $current_contents = $new;

  open(my $fh, '>', $temp_file) or die "Could not open $temp_file: $!";
  print $fh $new;
  close $fh;

  foreach my $session (qw(irc default)) {
    system(qw(/usr/bin/screen -S), $session,  qw(-X msgwait 0));
    system(qw(/usr/bin/screen -S), $session, qw(-X readbuf), $temp_file);
    system(qw(/usr/bin/screen -S), $session, qw(-X msgwait 2));
  }
}

sub get_clip {
  return `pbpaste`;
}
