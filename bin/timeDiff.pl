#!/opt/third-party/bin/perl 

use warnings;
use strict;

my $time1  = shift;
my $time2  = shift;
my $amount = shift;

$time1 = convert_to_seconds($time1);
$time2 = convert_to_seconds($time2);

my $diff = $time1 - $time2;

if ( $diff < 0 ) { $diff *= -1; }

print "seconds: $diff\n";

if ( $amount ) {
  my $tps = $amount / $diff;
  printf("tps: %.4f\n", $tps);
}

sub convert_to_seconds {
  my $time = shift;

  my $to_return;

  if ( $time =~ m/(\d*) (\d*):(\d*):(\d*)/ ) {
    $to_return = ($1 * 24 * 60 * 60 ) + ($2 * 60 * 60) + ($3 * 60) + $4;
  }
  elsif ( $time =~ m/\d+/ ) {
    $to_return = $time;
  }
  else {
    die "Could not parse time: $time\n";
  }
}
