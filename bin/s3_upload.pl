#!/usr/bin/perl

$|=1;

use strict;
use warnings;

use Getopt::Long;
use File::Basename qw(fileparse);

my $file;
my $upload_name;
my $bucket = 'bernard-public';
my $prompt_for_name = 0;

GetOptions(
  'file=s'        => \$file,
  'name|upload=s' => \$upload_name,
  'bucket=s'      => \$bucket,
  'help'          => \&usage,
  'prompt'        => \$prompt_for_name,
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

if ( $prompt_for_name && (!$upload_name) ) {
  my $extension = '.txt';
  if ( $file =~ m/(\..*)$/ ) {
    $extension = $1;
  }

  print "Upload name (will add $extension unless an extension is specified): ";
  my $input = <STDIN>;
  chomp $input;
  $upload_name = $input;

  if ( $input !~ m/\./ ) {
    # If there is no extension, add the extension
    $upload_name .= $extension;
  }
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
  --prompt  Prompt for a upload name, unless --name is specificed (--name
            overrides this option)

Example:
  # Upload a picture
  $0 mypic.jpg

  # Upload a .csv, changing the name
  $0 data.csv --name saved-data-for-bob.csv
USAGE
  exit 1;
}
