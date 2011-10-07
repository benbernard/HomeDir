#!/usr/bin/perl

use strict;
use warnings;

use Getopt::Long;

my $file;
my $upload_name;
my $bucket = 'bernard-public';

GetOptions(
  'file=s'        => \$file,
  'name|upload=s' => \$upload_name,
  'bucket=s'      => \$bucket,
  'help'          => \&usage,

);

if ( ! $file && $ARGV[0]) {
  if ( scalar @ARGV > 1 ) {
    die "Found extra arguments, can only upload one file at a time!\n";
  }
  $file = $ARGV[0];
}
elsif ( ! $file ) {
  die "Must specify a file to upload\n";
}

$upload_name ||= $file;

print "Uploading $file to s3\n";
system('s3cmd', '-P', "put", $file, "s3://$bucket/$upload_name");

print "Done Uploading $file. URL:\n";
print "  http://s3.amazonaws.com/$bucket/$upload_name\n";
print "  http://$bucket.s3.amazonaws.com/$upload_name\n";

sub usage {
  print <<USAGE;
$0 FILE
  Uploads a file to s3 with public accessibility in my public bucket

  --file    File to upload [optional, may specify it as a non-optioned
            parameter)
  --name    resulting name (defaults to --file)
  --bucket  bucket to upload to
  --upload  same as --name

Example:
  # Upload a picture
  $0 mypic.jpg

  # Upload a .csv, changing the name
  $0 data.csv --name saved-data-for-bob.csv
USAGE
  exit 1;
}
