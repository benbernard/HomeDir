#!/usr/bin/perl -w

use strict;
use warnings;

use FindBin qw($Bin); use lib $Bin . "/perl/lib";;

use Ratpoison;

my $rt = Ratpoison->new();

foreach my $frame (values %{$rt->get_screen_frames()} ) {
  next if ($frame->{screen_number} == 3 );
  $rt->fselect($frame->{'number'});
  $rt->select('-');
}
