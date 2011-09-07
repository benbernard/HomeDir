#!/usr/bin/perl -w

use strict;
use warnings;

use FindBin qw($Bin); use lib $Bin . "/perl/lib";;

use Ratpoison;
use Data::Dumper;

use Getopt::Long;

my ($name, $frame, $number, $exact_title, $re_title, $not_pattern);

GetOptions(
  'name=s'       => \$name,
  'frame=s'      => \$frame,
  'number=s'     => \$number,
  'title=s'      => \$re_title,
  'exactTitle=s' => \$exact_title,
  'not=s'        => \$not_pattern,
);

my $rt = Ratpoison->new();

my $windows = $rt->get_windows();

my $found;
foreach my $window (values %$windows) {
  my $title = $window->{'title'};
  
  next if ( ! match_title($title, $exact_title, $name, $not_pattern) );

  $found = $window;
  last;
}

die "Could not find window for $name" unless ($found);

my $win_number = $found->{'window_number'};

if ( $found->{'frame'} ne '' ) {
  $rt->select($win_number);
  sleep 1;
  $rt->select('-');
}


my $need_renumber = $win_number != $number;
my $fixed;
$fixed = fix_new_number($number, $found, $windows) if ( $need_renumber );

$rt->fselect($frame);
$rt->select($win_number);
$rt->title($re_title) if ( $re_title );
$rt->fselect($frame);
$rt->number($number) if ( (defined $number) && $need_renumber );

if ( $fixed ) {
  #sleep 1;
  $rt->select(999);
  $rt->number($win_number);
  $rt->select($number);
}

sub fix_new_number {
  my $number     = shift;
  my $new_window = shift;
  my $windows    = shift;

  my $current_window = $windows->{$number};
  
  return unless $current_window;
  $rt->select($number);
  $rt->number(999);
  return 1;
}

sub match_title {
  my $title       = shift;
  my $exact       = shift;
  my $regex       = shift;
  my $not_pattern = shift;

  return 1 if $exact && $title eq $exact;

  if ( $regex && $title =~ m/$regex/ ) {
    return 1 unless $not_pattern;
    return 0 if ( $title =~ m/$not_pattern/ );

    return 1;
  }

  return 0;
}
