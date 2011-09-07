#!/usr/bin/perl -w

use strict;
use warnings;

use FindBin qw($Bin); use lib $Bin . "/perl/lib";;

use Ratpoison;

use Getopt::Long;

my ($a, $b);

GetOptions(
  'a=s'   => \$a,
  'b=s'  => \$b,
);

my $rt = Ratpoison->new();

my $windows = $rt->get_windows();

my $a_window;
my $b_window;
foreach my $window (values %$windows) {
  my $title = $window->{'title'};

  if ( (! $a_window) && $title =~ m/$a/ ) {
    $a_window = $window;
  }

  if ( (! $b_window) && $title =~ m/$b/ ) {
    $b_window = $window;
  }
}

die "Could not find window for $a" unless ($a_window);
die "Could not find window for $b" unless ($b_window);

my ($from_window, $to_window);
if ( $a_window->{'frame'} eq '' ) {
  if ( $b_window->{'frame'} eq '' ) {
    die "Neither $a or $b is currently displayed";
  }
  else {
    $from_window = $b_window;
    $to_window = $a_window;
  }
}
else {
  $from_window = $a_window;
  $to_window = $b_window;
}

my $from_win_number = $from_window->{'window_number'};
my $to_win_number = $to_window->{'window_number'};


# Clear the current window
$rt->select($from_win_number);
$rt->select('-');

$rt->select($to_win_number);
$rt->number($from_win_number);
