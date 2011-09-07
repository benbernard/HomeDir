#!/usr/bin/perl -w

use strict;
use warnings;

use FindBin qw($Bin); use lib $Bin . "/perl/lib";;

use Ratpoison;

my $rt = Ratpoison->new();

my $new_num = 500;

foreach my $window (values %{$rt->get_windows()} ) {
  my $number = $window->{'window_number'};
  $rt->select($number);
  $rt->number($new_num);
  $new_num++;
}
