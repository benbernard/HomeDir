BEGIN {
  require FindBin;
  import FindBin qw($Bin);

  require lib;
  import lib $Bin . '/perl/lib';
}

1;
