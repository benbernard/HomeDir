" brazil_inc_path.vim
"
" Author: Dave Goodell <goodell@amazon.com>
" Description:
"   creates

au BufNewFile,BufReadPost   /workplace*/**   call UpdatePathForBrazil()

function! UpdatePathForBrazil()
  perl <<EOT

  my $target = (VIM::Eval('expand("%:p")'))[1];
  # uncomment to aid in debugging
  #`echo 'target=$target\n' >> /tmp/foo`;

  # bugfix for when you're using the bufexplorer.  expand("%:p") while in the
  # bufexplorer is something like this:
  #   /workplace/goodell/codigo-mainline/src/shared/platform/Codigo/[BufExplorer]
  unless ($target =~ /\[BufExplorer\]/ || $target =~ /__Tag_List__/ )
  {

    # We need to invoke with /apollo/bin/env -e in case our cwd is in a different
    # env where perl/bin/perl5.8/perl is present in cwd
    my $apollo_root = (VIM::Eval('g:ApolloRoot'))[1];
    my ($envAlias) = $apollo_root =~ m!([^/]+)$!;
    my $cmd = "/apollo/bin/env -e $envAlias perl/bin/perl5.8/perl -w $apollo_root/bin/gatherVimIncPath '$target'";
    # uncomment to aid in debugging
    #`echo 'cmd=$cmd\n' >> /tmp/foo`;

    my $np = `$cmd`;
    chomp $np;
    my @new_path = split(/,/, $np);
    my @old_path = split(/,/, (VIM::Eval('&path'))[1]);
    my @output_path = @old_path;
    my %old_path_hash = map { $_ => 1 } @old_path;
    foreach my $new (@new_path)
    {
      if (not exists $old_path_hash{$new})
      {
        push @output_path, $new;
      }
    }
    VIM::DoCommand("set path=" . join(',', @output_path));
  }
EOT
endfunction

