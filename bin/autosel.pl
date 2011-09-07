#!/usr/bin/perl -w

use strict;
use warnings;

use FindBin qw($Bin); use lib $Bin . "/perl/lib";;

use Expect;

use HumanStorable qw(store_file read_file);
use BufferRing;

use Getopt::Long;

my $verbose = 0;

GetOptions(
  'verbose' => \$verbose,
);

print "Verbose: $verbose\n";

my $exp = Expect->new();

use Data::Dumper;

#first make sure we're the only things running
system("killall autocutsel");

# we also need primary syced since firefox puts selected text there
my $autocutsel = $ENV{HOME} . "/apps/autocutsel-0.9.0/autocutsel";
system($autocutsel, '-selection', 'PRIMARY', '-fork');

$exp->spawn($autocutsel, qw(-d -v));
$exp->log_file(\&logger);
$exp->log_stdout(0);

my $ring = BufferRing->new();

my $accumulate = 0;
my $current_value = '';
sub logger {
  my $line = shift;
  chomp $line;

  if ( substr($line, length($line)-1, 1) eq chr(13) ) {
    chop $line;
  }

  if ( $line =~ m/\n/m ) {
    my @lines = split("\n", $line);
    logger($_) for @lines;
    return;
  }

  if ( $accumulate ) {
    if ( $line =~ m/^(.*)\036$/ ) {
      $current_value .= "\n$1";
      $ring->update_buffers();
      $ring->add_buffer($current_value);
      print "Setting multiline buffer $current_value\n" if ( $verbose );
      #print get_nums($current_value) . "\n" if ( $verbose );
      $current_value = '';
      $accumulate = 0;
      return;
    }
    else {
      $current_value .= "\n$line";
    }
  }

  my $rs = chr(30);

  if ( $line =~ m/^New value saved: \036(.*)\036$/ ) {
    my $value   = $1;
    print "Setting buffer: $value\n" if ( $verbose );
    #print get_nums($value) . "\n" if ( $verbose );
    $ring->update_buffers();
    my $buffer = $ring->add_buffer($value);
    $buffer->update_mac();
    return;
  }

  if ( $line =~ m/^New value saved: \036(.*)/ ) {
    $current_value = $1;
    $accumulate = 1;
    return;
  } 
}

sub get_nums {
  my $string = shift;

  my $str = '';
  for (my $i = 0; $i < length($string); $i++) {
    $str .= ord(substr($string, $i, 1)) . " ";
  }
  chop $str;
  return $str;
}

$exp->expect(undef);
