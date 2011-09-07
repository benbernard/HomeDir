#!/opt/third-party/bin/perl 

use warnings;
use strict;

my $time1 = shift;
my $time2 = shift;

$time1 = convert_to_seconds($time1);
$time2 = convert_to_seconds($time2);

my $factor = $time1 / $time2;

printf("Factor of %.2f\n", $factor);

sub convert_to_seconds {
  my $time = shift;

  my $to_return;

  if ( $time =~ m/(\d*):(\d*)/ ) {
    $to_return = ($1 * 60) + $2;
  }
  elsif ( $time =~ m/\d+/ ) {
    $to_return = $time;
  }
  else {
    die "Could not parse time: $time\n";
  }
}
