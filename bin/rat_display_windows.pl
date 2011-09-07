#!/usr/bin/perl -w

use warnings;
use strict;

use FindBin qw($Bin); use lib $Bin . "/perl/lib";;

use Ratpoison;

my $ratmen = '/usr/bin/ratmenu';

my $rt = Ratpoison->new();
my $windows = $rt->get_windows();

my @args;

my $position = 1;
my $selected_window = 0;
foreach my $window (sort { $a->{'window_number'} <=> $b->{'window_number'} } values %$windows) {
  my $title  = $window->{'title'};
  my $number = $window->{'window_number'};

  push @args, "$number - $title";
  push @args, "ratpoison -c 'select $number'";

  $selected_window = $position if ( $window->{'status'} eq '*' );
  $position++;
}

#exec($ratmen, '-i', $selected_window, @args);
exec($ratmen, @args);
