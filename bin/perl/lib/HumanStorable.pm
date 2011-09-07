package HumanStorable;

require Exporter;
@ISA = qw(Exporter);
@EXPORT_OK = qw(store_file read_file);  # symbols to export on request

use Data::Dumper;
use Fcntl ':flock'; # import LOCK_* constants
use File::Basename qw(dirname);
use File::Path qw(mkpath);

sub read_file {
  my $file    = shift;
  my $default = shift;

  return $default unless ( -e $file );

  local $/;
  open(my $fh, '<', $file) or die "Could not open $file: $1";
  flock($fh, LOCK_SH);
  my $info = <$fh>;
  flock($fh, LOCK_UN);
  close $fh;

  my $VAR1;
  eval $info;

  die $@ if ( $@ );
  return $VAR1 || $default;
}

sub store_file {
  my $file = shift;
  my $data = shift;

  my $dir = dirname($file);
  mkpath($dir) unless ( -e $dir );

  Data::Dumper::Purity(1);
  Data::Dumper::Indent(1);
  open (my $fh, '>', $file) or die "Could not open $file:$!";
  flock($fh, LOCK_EX);
  print $fh Dumper($data) . "\n";
  flock($fh, LOCK_UN);
  close $fh;
}

1;
