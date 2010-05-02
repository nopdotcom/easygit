#!/usr/bin/perl -w

## Easy GIT (eg), a frontend for git designed for former cvs and svn users
## Version 1.7.0.4.dev
## Copyright 2008-2010 by Elijah Newren, and others
## Licensed under GNU GPL, version 2.

## To use eg, simply stick this file in your path.  Then fire off an
## 'eg help' to get oriented.  You may also be interested in
##   http://www.gnome.org/~newren/eg/git-for-svn-users.html
## to get a comparison to svn in terms of capabilities and commands.
## Webpage for eg: http://www.gnome.org/~newren/eg

use strict;
use warnings;

package EasyGit::Command;

use EasyGit::Command::Common;

# set via has_command()
has command_name => (
    isa      => 'String',
    required => 1,
);

# Our "see also" section in help usually references the same subsection
# as our class name. This is exported into template help pages e.g. command.tt
# set via has_command
has git_equivalent => (
    isa      => 'String',
    required => 1,
);

# set via has_command()
has git_repo_needed => (
    isa      => 'Boolean',
    required => 1,
    default  => 0,
);

sub BUILD {
  # We allow direct instantiation of the subcommand class only if they
  # provide a command name for us to pass to git.
  if (ref($class) eq "subcommand" && not(defined $self->{command})) {
    die "Invalid subcommand usage"
  }

  # Most commands must be run inside a git working directory
  if ($self->{git_repo_needed} || not(@ARGV > 0 && $ARGV[0] eq "--help")) {
    $self->{git_dir} = EasyGit::RepoUtil::git_dir();
    die "Must be run inside a git repository!\n" unless defined $self->{git_dir};
  }

  # Many commands do not work if no commit has yet been made
  if ($self->{initial_commit_error_msg} && EasyGit::RepoUtil::initial_commit() && (@ARGV < 1 || $ARGV[0] ne "--help")) {
    die "$self->{initial_commit_error_msg}\n";
  }

  return $self;
}

method help {
  my $command_name = $self->command_name;

  if ($command_name eq "subcommand") {
    exit EasyGit::ExecUtil::execute("$GIT_CMD $self->{command} --help")
  }

  my $git_equiv = $self->git_equivalent;

  my $help = $self->load_help($command_name,
      {
	  git_equiv => $git_equiv,
	  command_name => $command_name,
      }
  );

  $ENV{LESS} //= 'FRSX';

  my $less = ($USE_PAGER == 1) ? 'less' :
             ($USE_PAGER == 0) ? 'cat' :
             `$GIT_CMD config core.pager` || 'less';
  chomp($less);
  open(OUTPUT, "| $less") or die "can't open $less for output";
  print OUTPUT "$command_name: $COMMAND{$package_name}->{about}\n";
  print OUTPUT $self->{help};
  print OUTPUT "\nDifferences from git $command_name:";
  print OUTPUT "\n  None.\n" unless defined $self->{differences};
  print OUTPUT $self->{differences} if defined $self->{differences};

  if ($git_equiv) {
    print OUTPUT "\nSee also\n";
    print OUTPUT <<EOF;
  Run 'git help $git_equiv' for a comprehensive list of options available.
  eg $command_name is designed to accept the same options as git $git_equiv, and
  with the same meanings unless specified otherwise in the above
  "Differences" section.
EOF
  }
  close(OUTPUT);
  exit 0;
}

method preprocess {
  return if (@ARGV and $ARGV[0] eq '--');
  my $result = main::GetOptions('--help' => sub { $self->help() });
}

method run {
  my $command_name = $self->command_name;
  my $subcommand = $command_name eq "subcommand" ? $self->{'command'} : $command_name;

  @ARGV = Util::quote_args(@ARGV);
  return ExecUtil::execute("$GIT_CMD $subcommand @ARGV", ignore_ret => 1);
}

###########################################################################
# add                                                                     #
###########################################################################

package EasyGit::Command::Add;

use EasyGit::Command::Common;

extends 'EasyGit::Command';

has_command add => (
    unmodified_behavior => 1,
    section             => 'compatibility',
    about               => 'Mark content in files as being ready for commit'
    git_repo_needed     => 1,
);

###########################################################################
# apply                                                                   #
###########################################################################

package EasyGit::Command::Apply;

use EasyGit::Command::Common;

has_command apply => (
    about => 'Apply a patch in a git repository'
);

method preprocess {
  my $result = main::GetOptions("--help" => sub { $self->help() });
  @ARGV = map { ($_ eq '--staged') ? '--cached' : $_ } @ARGV;
}

###########################################################################
# branch                                                                  #
###########################################################################

package EasyGit::Command::Branch;

use EasyGit::Command::Common;

has_command branch => (
    section         => 'projects',
    about           => 'List, create, or delete branches',
    git_repo_needed => 1,
    alias           => 'br'
);

method run {
  my $switch = 0;

  if (@ARGV and $ARGV[0] eq '-s') {
    shift @ARGV;
    $switch = 1;
  }

  @ARGV = Util::quote_args(@ARGV);
  my $ret = ExecUtil::execute("$GIT_CMD branch @ARGV", ignore_ret => 1);
  $ret = ExecUtil::execute("$GIT_CMD checkout $ARGV[0]", ignore_ret => 1) if ($switch && $ret == 0);
  return $ret;
}

###########################################################################
# bundle                                                                  #
###########################################################################

package EasyGit::Command::Bundle;

use EasyGit::Command::Common;

has_command bundle => (
    extra                    => 1,
    section                  => 'collaboration',
    about                    => 'Pack repository updates (or whole repository) into a file',
    git_repo_needed          => 1,
    initial_commit_error_msg => 'No bundles can be created until a commit has been made.',
);

method preprocess {
    # Parse options
    my @args;
    my $result = main::GetOptions("--help" => sub { $self->help() });

    # Get the (sub)subcommand
    $self->{subcommand} = shift @ARGV;
    push(@args, $self->{subcommand});

    if ($self->{subcommand} eq 'create') {
        my $filename = shift @ARGV || die "Error: need a filename to write bundle to.\n";
        push(@args, $filename);    # Handle the filename

        unless (@ARGV) {
            push(@args, ('--all', 'HEAD'));
        }
    } elsif ($self->{subcommand} eq 'create-update') {
        pop(@args);                # 'create-update' isn't a real git bundle subcommand

        my $newname = shift @ARGV || die "You must specify a new and an old filename.\n";
        my $oldname = shift @ARGV || die "You must also specify an old filename\n";

        die "$oldname does not exist.\n" unless -f $oldname;

        my ($retval, $output) = ExecUtil::execute_captured("$GIT_CMD bundle list-heads $oldname");
        my @lines = split '\n', $output;
        my @refs = map { m#^([0-9a-f]+)# && "^$1" } @lines;

        push(@args, ('create', $newname, '--all', 'HEAD', @refs));
    }

    push(@args, @ARGV);

    # Reset @ARGV with the built up list of arguments
    @ARGV = @args;
}

###########################################################################
# cat                                                                     #
###########################################################################

package EasyGit::Command::Cat;

use EasyGit::Command::Common;

has_command cat => (
    new_command              => 1,
    extra                    => 1,
    section                  => 'compatibility',
    about                    => 'Output the current or specified version of files',
    git_repo_needed          => 1,
    git_equivalent           => 'show',
    initial_commit_error_msg => 'Error: Cannot show committed versions of files when no commits have occurred.',
);

method preprocess {
  my $result = main::GetOptions("--help" => sub { $self->help() });

  # Get important directories
  my ($cur_dir, $top_dir, $git_dir) = RepoUtil::get_dirs();

  my @args;
  for my $arg (@ARGV) {
    if ($arg !~ /:/) {
      my ($path) = Util::reroot_paths__from_to_files($cur_dir, $top_dir, $arg);
      push(@args, "HEAD:$path");
    } else {
      my ($REVISION, $FILE) = split(/:/, $arg, 2);
      my ($path) = Util::reroot_paths__from_to_files($cur_dir, $top_dir, $FILE);
      push(@args, "$REVISION:$path");
    }
  }

  @ARGV = @args;
}

method run {
  return ExecUtil::execute([ $GIT_CMD, 'show', @ARGV ], ignore_ret => 1);
}

1;

package EasyGit::Changes;

use EasyGit::Command::Common;

has_command changes => (
    new_command     => 1,
    section         => 'misc',
    about           => 'Provide an overview of the changes from git to eg',
    git_repo_needed => 1,
    git_equivalent  => '',
);

sub preprocess {
    my $self = shift;

    $self->{details} = 0;

    my $result = main::GetOptions(
        "--help" => sub { $self->help() },
        "--details" => \$self->{details},
    );

    die "Unrecognized arguments: @ARGV\n" if @ARGV;
}

sub run {
  my $self = shift;

  if ($DEBUG == 2) {
    print "    >>(No commands to run, just data to print)<<\n";
    return;
  }

  # Print valid subcommands sorted by section
  my $indent = "  ";
  my $header_indent = "";
  $ENV{"LESS"} = "FRSX" unless defined $ENV{"LESS"};
  my $less = ($USE_PAGER == 1) ? "less" :
             ($USE_PAGER == 0) ? "cat" :
             `$GIT_CMD config core.pager` || "less";
  chomp($less);
  open(OUTPUT, "| $less");

  if ($self->{details}) {
    print OUTPUT "Summary of changes:\n";
    $indent = "    ";
    $header_indent = "  ";
  }
  print OUTPUT "${header_indent}Modified Behavior:\n";
  foreach my $c (sort keys %COMMAND) {
    next if $COMMAND{$c}{unmodified_behavior};
    next if $COMMAND{$c}{new_command};
    print OUTPUT "$indent$c\n";
  }
  print OUTPUT "${header_indent}New commands:\n";
  foreach my $c (sort keys %COMMAND) {
    next if !$COMMAND{$c}{new_command};
    print OUTPUT "$indent$c\n";
  }
  print OUTPUT "${header_indent}Modified Help Only:\n";
  foreach my $c (sort keys %COMMAND) {
    next if $COMMAND{$c}{unmodified_help};
    next if !$COMMAND{$c}{unmodified_behavior};
    next if $COMMAND{$c}{new_command};
    print OUTPUT "$indent$c\n";
  }

  if ($self->{details}) {
    foreach my $c (sort keys %COMMAND) {
      next if $COMMAND{$c}{unmodified_help} || $COMMAND{$c}{unmodified_behavior};

      my $real_c = $c;
      $c =~ s/-/_/;  # Packages use underscores, commands use dashes
      next if !$c->can("new");
      my $obj = $c->new(initial_commit_error_msg => '');

      print OUTPUT "Changes to $real_c:\n";
      if ($obj->{differences}) {
        $obj->{differences} =~ s/^\n//;
        print OUTPUT $obj->{differences};
      } else {
        print OUTPUT "  <Unknown>.\n";
      }
    }
  }
  close(OUTPUT);
}

1;

###########################################################################
# checkout                                                                #
###########################################################################

package EasyGit::Command::Checkout;

use EasyGit::Command::Common;

has_command checkout => (
    section => 'compatibility',
    about   => 'Compatibility wrapper for clone/switch/revert'
);

sub _looks_like_git_repo ($) {
  my $path = shift;

  my $clone_protocol = qr#^(?:git|ssh|http|https|rsync)://#;
  my $git_dir = RepoUtil::git_dir();
  my $in_working_copy = defined $git_dir ? 1 : 0;

  # If the path looks like a git, ssh, http, https, or rsync url, then it
  # looks like we're being given a url to a git repo
  if ($path =~ /$clone_protocol/) {
    return 1;
  }

  # If the path isn't a clone_protocol url and isn't a directory, it can't be
  # a git repo
  if (! -d $path) {
    return 0;
  }

  my $path_is_absolute = ($path =~ m#^/#);
  return (!$in_working_copy || ($in_working_copy && $path_is_absolute));
}

sub preprocess {
  my $self = shift;

  if (scalar(@ARGV) > 0 && $ARGV[0] ne "--") {
    main::GetOptions("--help" => sub { $self->help() });
  }

  $self->{command} = 'checkout';
  die "eg checkout requires at least one argument.\n" if !@ARGV;

  # Determine whether this should be a call to git clone or git checkout
  my $clone_protocol = qr#^(?:git|ssh|http|https|rsync)://#;

  if (_looks_like_git_repo($ARGV[-1]) ||
      (! -d $ARGV[-1] && @ARGV > 1 && _looks_like_git_repo($ARGV[-2]))
     ) {
    $self->{command} = 'clone';
  }
}

sub run {
  my $self = shift;

  if ($self->{command} ne 'clone') {
    # If this operation isn't a clone, then we should have checked for
    # whether we are in a git directory.  But we didn't do that, just in
    # case it was a clone.  So, do it now.
    $self->{git_dir} = RepoUtil::git_dir();
    die "Must be run inside a git repository!\n" if !defined $self->{git_dir};

    return ExecUtil::execute([ $GIT_CMD, 'checkout', @ARGV ], ignore_ret => 1);
  } else {
    die "Did you mean to run\n  eg clone @ARGV\n?\n";
  }
}

1;

###########################################################################
# cherry_pick                                                             #
###########################################################################

package cherry_pick;

use EasyGit::Command::Common;

has_command 'cherry-pick' => (
    extra           => 1,
    section         => 'modification',
    about           => 'Apply (or reverse) a commit, usually from another branch',
    git_repo_needed => 1,
);

sub preprocess {
  my $self = shift;

  my ($reverse, $dash_x, $mainline) = (0, 0, -1);
  Getopt::Long::Configure("permute"); # Allow unrecognized options through
  my $result = main::GetOptions(
    "--help"       => sub { $self->help() },
    "mainline|m=i" => \$mainline,
    "reverse|R"    => \$reverse,
    "revert"       => \$reverse,
    "x"            => \$dash_x,
    );
  $self->{reverse} = $reverse;
  unshift(@ARGV, "-x") if (!$reverse && $dash_x);
  unshift(@ARGV, ("-m", $mainline)) if $mainline != -1;
}

sub run {
  my $self = shift;

  if ($self->{reverse}) {
    return ExecUtil::execute([ $GIT_CMD, 'revert', @ARGV ], ignore_ret => 1);
  } else {
    return ExecUtil::execute([ $GIT_CMD, 'cherry-pick', @ARGV ], ignore_ret => 1);
  }
}

###########################################################################
# clone                                                                   #
###########################################################################

package EasyGit::Command::Clone;

use EasyGit::Command::Common;

has_command clone => (
    section => 'creation',
    about => 'Clone a repository into a new directory'
);

sub preprocess {
  my $self = shift;

  $self->{bare} = 0;
  my @old_argv = @ARGV;
  Getopt::Long::Configure("permute");
  my $result = main::GetOptions(
    "help"             => sub { $self->help() },
    "bare"             => sub { $self->{bare} = 1 },
    "mirror"           => sub { $self->{bare} = 1 },
    "branch|b=s",
    "depth=i",
    "origin|o=s",
    "reference=s",
    "upload-pack|u=s",
    );
  shift @ARGV while ($ARGV[0] =~ /^-/);  # Skip past any other options
  $self->{repository} = shift @ARGV;
  die "No repository specified!\n" unless $self->{repository};
  my $basename = $self->{repository};
  $basename =~ s#/*$##;        # Remove trailing slashes
  $basename =~ s#.*[/:]##;     # Remove everything but final dirname
  $basename =~ s#\.git$##;     # Remote .git suffix, if present
  $basename =~ s#\.bundle$##;  # Remote .bundle suffix, if present
  $self->{directory} = shift @ARGV || $basename . ($self->{bare} ? ".git" : "");
  die "Too many parameters to clone!\n" if (scalar(@ARGV) > 0);

  @ARGV = @old_argv;  # Workaround: GetOptions may have stripped a leading '--'
}

sub run {
  my $self = shift;

  # Perform the clone
  my $ret = ExecUtil::execute([ $GIT_CMD, 'clone', @ARGV ], ignore_ret => 1);
  return $ret if $self->{bare};

  if ($DEBUG > 1) {
    print "    >>Running: 'cd $self->{directory}'<<\n";
    print "    >>Running: '$GIT_CMD branch -r'<<\n";
    print "    --- Setting up extra branches by default ---\n";
    print "    >>Running, for each remote branch besides master (referred to as BRANCH):\n";
    print "        $GIT_CMD branch BRANCH origin/BRANCH\n";
  } elsif ($ret == 0) {
    # Switch to the appropriate directory, remembering the repository we
    # checked out
    die "$self->{directory} does not exist after checkout!"
      unless -d $self->{directory};
    $self->{repository} = main::abs_path($self->{repository})
      if -d $self->{repository};
    chdir($self->{directory});

    # Determine local and remote branches
    my @remote_branches =
      split('\n', `$GIT_CMD for-each-ref --format '%(refname)' refs/remotes`);
    @remote_branches = map { m#^refs/remotes/(.*)$# && $1 } @remote_branches;
    my @local_branches =
      split('\n', `$GIT_CMD for-each-ref --format '%(refname)' refs/heads`);
    @local_branches = map { m#^refs/heads/(.*)$# && $1 } @local_branches;

    # Set branch.@local_branches.rebase to true if branch.autosetuprebse is true
    my $autosetuprebase = `$GIT_CMD config --global branch.autosetuprebase`;
    chomp($autosetuprebase);
    if ($autosetuprebase eq 'always' || $autosetuprebase eq 'remote') {
      foreach my $branch (@local_branches) {
        ExecUtil::execute([ $GIT_CMD, 'config', "branch.$branch.rebase", 'true' ]);
      }
    }

    # Set up a branch for each remote branch, not just master
    foreach my $b (@remote_branches) {
      my ($remote, $branch) = ($b =~ m#^(.*)/(.*?)$#);
      next if $branch eq "HEAD";
      next if grep {$branch eq $_} @local_branches;
      ExecUtil::execute([ $GIT_CMD, 'branch', $branch, "$remote/$branch", '>' '/dev/null' ]);
    }
  }

  return $ret;
}

1;

###########################################################################
# commit                                                                  #
###########################################################################

package EasyGit::Command::Commit;

use EasyGit::Command::Common;

has_command commit => (
    section         => 'modification',
    about           => 'Record changes locally',
    git_repo_needed => 1,
    alias           => [ 'checkin', 'ci' ]
);

sub preprocess {
  my $self = shift;
  my $package_name = ref($self);

  #
  # Parse options
  #
  $self->{args} = [];
  my $record_arg   = sub { push(@{$self->{args}}, "$_[0]$_[1]"); };
  my $record_args  = sub { push(@{$self->{args}}, "$_[0]$_[1]");
                           push(@{$self->{args}}, splice(@_, 2)); };
  my ($all_known, $bypass_unknown, $staged, $amend,
      $dry_run, $allow_empty, $include) = (0, 0, 0, 0, 0, 0, 0);
  Getopt::Long::Configure("permute");
  my $result = main::GetOptions(
    "--help"                      => sub { $self->help() },
    "all-known|a"                 => \$all_known,
    "bypass-unknown-check|b"      => \$bypass_unknown,
    "staged|dirty|d"              => \$staged,
    "dry-run"                     => sub { $dry_run = 1, &$record_arg("--", @_) },
    "s"                           => sub { &$record_arg("-", @_) },
    "v"                           => sub { &$record_arg("-", @_) },
    "u"                           => sub { &$record_arg("-", @_) },
    "c=s"                         => sub { &$record_args("-", @_) },
    "C=s"                         => sub { &$record_args("-", @_) },
    "F=s"                         => sub { &$record_args("-", @_) },
    "file=s"                      => sub { &$record_args("--", @_) },
    "m=s"                         => sub { &$record_args("-", @_) },
    "amend"                       => sub { $amend = 1; &$record_arg("--", @_) },
    "allow-empty"                 => sub { $allow_empty = 1; &$record_arg("--", @_) },
    "interactive"                 => sub { $allow_empty = 1; &$record_arg("--", @_) },
    "no-verify"                   => sub { &$record_arg("--", @_) },
    "e"                           => sub { &$record_arg("-", @_) },
    "author=s"                    => sub { &$record_args("--", @_) },
    "cleanup=s"                   => sub { &$record_args("--", @_) },
    "include|i=s"                 => sub { $include = 1; &$record_args("--", @_) },
    );
  my ($opts, $revs, $files) = RepoUtil::parse_args([], @ARGV);

  # Set up flags based on options, do sanity checking of options
  my ($check_no_changes, $check_unknown, $check_mixed, $check_unmerged);
  my $skip_all = $include || $dry_run;
  $self->{commit_flags} = [];
  die "Cannot specify both --all-known (-a) and --staged (-d)!\n" if
    $all_known && $staged;
  die "Cannot specify --staged when specifying files!\n" if @$files && $staged;
  $check_no_changes = !$amend && !$allow_empty && !$skip_all;
  $check_unknown   = !$bypass_unknown && !$staged && !@$files && !$skip_all;
  $check_mixed     = !$all_known      && !$staged && !@$files && !$skip_all;
  $check_unmerged  = !$skip_all;
  push(@{$self->{commit_flags}}, "-a") if $all_known;

  # Lots of sanity checks
  my $status =
    RepoUtil::commit_push_checks($package_name,
                                 {no_changes       => $check_no_changes,
                                  unknown          => $check_unknown,
                                  partially_staged => $check_mixed,
                                  unmerged_changes => $check_unmerged});

  if ($amend && !$all_known && !$staged && !$skip_all && !@$files &&
      $status->{has_unstaged_changes} && !$status->{has_staged_changes}) {
    print STDERR <<EOF;
Aborting: It is not clear whether you want to simply amend the commit
message or whether you want to include your local changes in the amended
commit. Please pass --staged to just amend the previous commit message, or
pass -a to include your current local changes with the previous amended
commit.
EOF
    exit 1;
  }

  die "No staged changes, but --staged given.\n"
      if (!$status->{has_staged_changes} && $staged && !$amend && !$dry_run);

  if (!$all_known && !$include && !$staged &&
      $status->{has_unstaged_changes} && !$status->{has_staged_changes} &&
      !@$files) {
    push(@{$self->{'commit_flags'}}, "-a");
  }

  # Record the set of unknown files we ignored with -b, so the -b flag isn't
  # needed next time.
  if ($bypass_unknown) {
    RepoUtil::record_ignored_unknowns();
  }

  push(@{$self->{args}}, @{$self->{commit_flags}});
  unshift(@ARGV, @{$self->{args}});
}

###########################################################################
# config                                                                  #
###########################################################################

package EasyGit::Command::Config;

use EasyGit::Command::Common;

has_command config => (
    unmodified_behavior => 1,
    extra               => 1,
    section             => 'misc',
    about               => 'Get or set configuration options',
    git_repo_needed     => 0
);

1;

###########################################################################
# diff                                                                    #
###########################################################################

package EasyGit::Command::Diff;

use EasyGit::Command::Common;

has_command diff => (
    section => 'discovery',
    about => 'Show changes to file contents',
    git_repo_needed => 1
);

sub preprocess {
  my $self = shift;

  # Avoid Util::git_rev_parse because it fails on t2010-checkout-ambiguous by
  # treating "--quiet" as a revision rather than an option; use our own
  # parse_args implementation instead.
  my ($opts, $revs, $files) = RepoUtil::parse_args(["--extcmd", "-x"], @ARGV);

  # Replace '..' with '...' in revision specifiers.  Use backslash escaping to
  # get actual dots and not just any character.  Use negative lookbehind and
  # lookahead assertions to avoid replacing '...' with '....'.
  my @new_revs = map(m#(.+)(?<!\.)\.\.(?!\.)(.+)# ? "$1...$2" : $_, @$revs);
  $revs = \@new_revs;

  #
  # Parse options
  #
  $self->{'opts'} = "";
  @ARGV = @$opts;
  my ($staged, $unstaged, $no_index) = (0, 0, 0);
  my $extcmd;
  Getopt::Long::Configure("permute");
  my $result = main::GetOptions(
    "--help"         => sub { $self->help() },
    "staged|cached"  => \$staged,
    "unstaged"       => \$unstaged,
    "no-index"       => \$no_index,
    "extcmd=s"       => \$extcmd,
    );
  die "Cannot specify both --staged and --unstaged!\n" if $staged && $unstaged;
  my @args;
  push(@args, "--cached") if $staged;
  push(@args, "--no-index") if $no_index;
  push(@args, "--extcmd", $extcmd) if $extcmd;
  push(@args, @ARGV);

  #
  # Parse revs
  #
  die "eg diff: Cannot specify '--staged' with more than 1 revision.\n"
    if ($staged && scalar @$revs > 1);
  die "eg diff: Cannot specify '--unstaged' with any revisions.\n"
    if ($unstaged && scalar @$revs > 0);
  # 'eg diff' (without arguments) should act like 'git diff HEAD', unless
  # we are in an aborted merge state 
  if (!@$revs && !$unstaged && !$staged && !$no_index) {
    if (-f "$self->{git_dir}/MERGE_HEAD") {
      my @merge_branches = RepoUtil::merge_branches();
      my $list = join(", ", @merge_branches);
      print STDERR <<EOF;
Aborting: Cannot show the changes since the last commit, since you are in the
middle of a merge and there are multiple last commits.  Try passing one of
  --unstaged, $list
to eg diff.

For additional conflict resolution help, try eg log --merge or
  eg show BRANCH:FILE
where FILE is any file in your working copy and BRANCH is one of
  $list
EOF
      exit 1;
    }
    if (RepoUtil::initial_commit()) {
      print STDERR <<EOF;
Aborting: Cannot show the changes since the last commit, since you do not
yet have any commits on the current branch.  Try passing --unstaged to diff,
or making a commit first.
EOF
      exit 1;
    }
    push(@$revs, "HEAD")
  }

  push(@args, @$revs);
  push(@args, "--");
  push(@args, @$files);
  @ARGV = @args;
}

1;

###########################################################################
# difftool                                                                #
###########################################################################

package difftool;

use EasyGit::Command::DiffTool;

has_command difftool => (
    new_command     => 1,
    extra           => 1,
    section         => 'discovery',
    about           => 'Show changes to file contents using an external tool',
    git_repo_needed => 1
);

1;

###########################################################################
# gc                                                                      #
###########################################################################

package EasyGit::Command::GC;

use EasyGit::Command::Common;

has_command gc => (
    unmodified_behavior => 1,
    extra               => 1,
    section             => 'timesavers',
    about               => 'Optimize the local repository to make later operations faster',
    git_repo_needed     => 1
);

1;

###########################################################################
# help                                                                    #
###########################################################################
package EasyGit::Command::Help;

use EasyGit::Command::Common;

has_command help => (
    section         => 'misc',
    about           => 'Get command syntax and examples',
    exit_status     => 0,
    git_equivalent  => '',
    git_repo_needed => 0,

);

sub preprocess {
    my $self = shift;

    $self->{all} = 0;

    my $result = main::GetOptions("--help" => sub { $self->help() },
        "--all" => \$self->{all});
}

sub run {
  my $self = shift;

  if ($DEBUG > 1) {
    print "    >>(No commands to run, just data to print)<<\n";
    return;
  }

  # Check if we were asked to get help on a subtopic rather than toplevel help
  if (@ARGV > 0) {
    my $orig_subcommand = shift @ARGV;
    my $subcommand = $orig_subcommand;
    $subcommand =~ s/-/_/;  # Packages use underscores, commands use dashes
    if (@ARGV != 0 && ($subcommand ne 'topic' || @ARGV != 1)) {
      die "Too many arguments to help.\n";
    }
    die "Oops, there's a bug.\n" if $self->{exit_status} != 0;
    $subcommand = "help::topic" if $subcommand eq 'topic';

    unless ($subcommand->can('new')) {
      print "$orig_subcommand is not modified by eg (eg $orig_subcommand is" .
            " equivalent to git $orig_subcommand).\nWill try running 'git" .
            " help $orig_subcommand' in 2 seconds...\n";
      sleep 2;
      exit ExecUtil::execute("$GIT_CMD help $orig_subcommand");
    }

    my $subcommand_obj = $subcommand->new(initial_commit_error_msg => '',
                                          git_repo_needed => 0);
    $subcommand_obj->help();
  }

  # Set up a pager, if wanted
  $ENV{"LESS"} = "FRSX" unless defined $ENV{"LESS"};
  my $less = ($USE_PAGER == 1) ? "less" :
             ($USE_PAGER == 0) ? "cat" :
             `$GIT_CMD config core.pager` || "less";
  chomp($less);
  open(OUTPUT, "| $less");

  # Help users know about the --all switch
  if (!$self->{all}) {
    print OUTPUT "(Run 'eg help --all' for a more detailed list.)\n\n";
  }

  # Print valid subcommands sorted by section
  foreach my $name (sort
                    {$SECTION->{$a}{'order'} <=> $SECTION->{$b}{'order'}}
                    keys %$SECTION) {
    next if $SECTION->{$name}{extra} && !$self->{all};
    print OUTPUT "$SECTION->{$name}{desc}\n";
    foreach my $c (sort keys %COMMAND) {
      next if !defined $COMMAND{$c}{section};
      next if $COMMAND{$c}{section} ne $name;
      next if $COMMAND{$c}{extra} && !$self->{all};
      printf OUTPUT "  eg %-11s %s\n", $c, $COMMAND{$c}{about};
    }
    print OUTPUT "\n";
  }

  # Check to see if someone added a command with an invalid section
  my $broken_commands = "";
  foreach my $c (keys %COMMAND) {
    next if !defined $COMMAND{$c}{section};
    next if defined $SECTION->{$COMMAND{$c}{section}};
    my $tmp = sprintf("  eg %-10s %s\n", $c, $COMMAND{$c}{about});
    $broken_commands .= $tmp;
  }
  if ($broken_commands) {
    print OUTPUT "Broken (typo in classification?) commands:\n" .
                 "$broken_commands\n";
  }

  # And let them know how to get more detailed help...
  print OUTPUT "Additional help:\n";
  print OUTPUT "  eg help COMMAND      Get more help on COMMAND.\n";
  print OUTPUT "  eg help --all        List more commands (not really all)\n";
  print OUTPUT "  eg help topic        List specialized help topics.\n";

  # And let them know how to compare to git
  if ($self->{all}) {
    print OUTPUT "\n";
    print OUTPUT "Learning or comparing to git\n";
    print OUTPUT "  eg --translate ARGS  Show commands that would be executed for 'eg ARGS'\n";
    print OUTPUT "  eg --debug ARGS      Show & run commands that would be executed by 'eg ARGS'\n";
  }

  close(OUTPUT);
  
  exit $self->{exit_status};
}

1;

###########################################################################
# help::topic                                                             #
###########################################################################

package help::topic;

sub new {
  my $class = shift;
  my $self = {};
  bless($self, $class);
  return $self;
}

sub middle_of_am {
  my $continue_text = "
1. Standard case

When all conflicts have been resolved, run
  eg am --resolved
Do NOT run \"eg commit\" to continue an interrupted rebase (unless you want
to manually insert a new commit; if you already accidentally ran eg commit,
then run 'eg reset HEAD~1' to undo it).  If you try to continue without
resolving all conflicts, the command will error out and tell you that some
conflicts remain to be resolved.

2. Special case -- skipping a commit

If you do not want this particular commit to be included in the final
result, run
  eg am --skip";
  my $abort_text = "
To abort your rebase operation, simply run
  eg am --abort";

  return _conflict_resolution_message(op => "am",
                                      show_empty_case => 1,
                                      continue_text => $continue_text,
                                      abort_text => $abort_text
                                      );
}

sub middle_of_merge {
  my $completion_text = "
When all conflicts have been resolved, run
  eg commit

The log message will be pre-populated with a sample commit message for you,
noting the merge and any file conflicts.  If you try to run this command
without resolving all conflicts, the command will error out and tell you
that some conflicts remain to be resolved.";
  my $abort_text = "
If you had no uncommitted changes before the merge (or do not care about
keeping those changes), you can run
  eg reset --working-copy ORIG_HEAD

If you had uncommitted changes before starting the merge, and have
git-1.6.2 or later, you can try
  eg ls-files --unmerged | awk {'print \$4'} | uniq | xargs eg stage
  eg reset --merge ORIG_HEAD
The first command will mark all unmerged files as ready for commit (who
doesn't like having conflict markers in their files?), and the second
command undoes all changes to staged files since ORIG_HEAD -- both the
files that were successfully merged by git, and the files that you manually
staged in the first command.";
  return _conflict_resolution_message(op => "merge",
                                      show_empty_case => 0,
                                      continue_text => $completion_text,
                                      abort_text => $abort_text);
}

sub middle_of_rebase {
  my $extra_stop_info = "

If you are in the middle of an interactive rebase (i.e. you specified the
--interactive flag), then rebase can also stop if you selected to edit a
commit, even when there are no conflicts.  In such a case where there are
no conflicts, there is something else you may want to do:
  5) Editing during an interactive rebase
Before telling git to continue the operation.";
  my $continue_text = "
1. Standard case

When all conflicts have been resolved, run
  eg rebase --continue
Do NOT run \"eg commit\" to continue an interrupted rebase (unless you want
to manually insert a new commit; if you already accidentally ran eg commit,
then run 'eg reset HEAD~1' to undo it).  If you try to continue without
resolving all conflicts, the command will error out and tell you that some
conflicts remain to be resolved.

2. Special case -- skipping a commit

If you do not want this particular commit to be included in the final
result, run
  eg rebase --skip";
  my $abort_text = "
To abort your rebase operation, simply run
  eg rebase --abort";
  my $interactive_edit_text = "
******************* Editing during an interactive rebase *******************

When an interactive rebase stops to allow you to edit a commit, make any
necessary changes to files, then run
  eg commit --amend
If you do not use the --amend flag, you will be inserting a new commit
after the one you chose to edit.

After you are done amending the previous commit (and/or commit message),
run 'eg rebase --continue' to allow the rebase operation to continue.
";
  return _conflict_resolution_message(op => "rebase",
                                      show_empty_case => 1,
                                      extra_stop_info => $extra_stop_info,
                                      continue_text => $continue_text,
                                      abort_text => $abort_text,
                                      final_text => $interactive_edit_text,
                                      );
}

sub _conflict_resolution_message (%) {
  my $opts = {op              => "!!!FIXME!!!",
              show_empty_case => 0,
              extra_stop_info => '',
              continue_text   => '!!!FIXME!!!',
              abort_text      => '!!!FIXME!!!',
              final_text      => '',
              @_};  # Hashref initialized as we're told
  my $result = "
When conflicting changes are detected, a $opts->{op} operation will stop to
allow a user to resolve the conflicts. At this stage there is one of four
things a user may want to do:
  1) Find out more about what conflicts occurred
  2) Resolve the conflicts
  3) Tell git to complete the operation
  4) Abort the operation
Each will be discussed below.$opts->{extra_stop_info}

*************** Find out more about what conflicts occurred ***************

1. Standard case

In order to find out which files have conflicts, run
  eg status
and then look for lines that begin with \"unmerged:\".  You can then open
the relevant file in an editor and look for lines with conflict markers,
i.e. lines that start with one of
  <<<<<<<
  =======
  >>>>>>>
Between the <'s and the ='s will be one version of the changed file, while
betwen the ='s and the >'s will be another version.

2. Simple tip

Since git will stage any changes it is able to successfully merge, you can
find the unresolved conflict sections of a file by running
  eg diff --unstaged FILE
";
  if ($opts->{show_empty_case}) {
  $result .= "
3. Special empty commit case

Sometimes, during a $opts->{op}, the changes in a commit will no longer be
necessary since they have already been included in the code which your
commit is being applied on top of.  In such a case, eg status will simply
show that there are no changes at all, and you can continue by telling git
to skip the current unneeded commit (see below).

4. Difficult cases
"
  } else {
  $result .= "
3. Difficult cases
";
  }
  $result .= "
You can run
  eg ls-files --unmerged
to get a list of all files in the unmerged state.  This will list up to
three lines for each file, and look like the following:
  100644 45b983be36b73c0788dc9cbcb76cbb80fc7bb057 1	foo.C
  100644 ce013625030ba8dba906f756967f9e9ca394464a 2	foo.C
  100644 dd7e1c6f0fefe118f0b63d9f10908c460aa317a6 3	foo.C
The first line corresponds to a version of the file at some common point in
history, the second and third lines correspond to different versions of the
file being merged (relative to the common version).  Each line is of the
form
  mode   internal-object-name                     stage filename
The mode represents the permission bits and or type (executable file,
symlink etc.), the internal-object-name is git's internal name for the
contents of the file, the stage is a simple integer, and you should
recognize the filename.

You can make use of this information to detect the following situations:
  A) There's a conflict in mode change (e.g. removed the executable bit on
     one side of history, turned the file into a symlink in another)
  B) The file is deleted in one version and modified in another (when this
     happens either the 2nd or 3rd stage line will be missing)
Further, you can view the different versions of the file easily, by using
either of:
  eg show :STAGE:FILENAME
  eg show INTERNAL-OBJECT-NAME
Some examples using the output above:
  eg show :2:foo.C
  eg show dd7e1c6f0fefe118f0b63d9f10908c460aa317a6

************************** Resolve the conflicts **************************

1. Standard case.

For each file with conflicts, edit the file to remove the conflict markers
and provide just the correct version of the merged file.  Then run
  eg stage FILE
to tell git that you have resolved the conflicts in FILE.

2. Special cases

Nearly all special cases (and even the standard case) boil down to making
sure the file has the correct contents, the correct permission bits and
type, and then running
  eg stage FILE

If the file is a binary, then there will not be any conflict markers.  In
such a case, simply ensure that the contents of the file are what you want
and then run eg stage, as noted above.

If the file is deleted on one side of history and changed in another,
decide what contents the file should have.  If the correct resolution is to
delete the file, run
  eg rm FILE
Otherwise, put the appropriate contents in the file and run eg stage as
noted above.

If the file has a mode conflict, then fix up the mode of the file (run
'man chmod' and 'man ln' for help on how to do so).  Note that the modes
used by git are as follows:
  100644  --  Normal, non-executable file
  100755  --  File with the executable bit set
  120000  --  symlink
  160000  --  A git submodule (run 'git help submodule' for more info)

******************** Tell git to continue the operation ********************
$opts->{continue_text}

*************************** Abort the operation ***************************
$opts->{abort_text}
";
  $result .= $opts->{final_text};
  return $result;
}

sub middle_of_bisect {
  return "
When git is bisecting, it will pick commits that need to be tested, check
them out, and then let you test them.  (Unless, of course, you give git a
script that it can run to automatically test commits.)  At this point you
can test and then:

1) Continue

  eg bisect good    # Mark the current commit as good, give me a new commit
OR
  eg bisect bad     # Mark the current commit as bad, give me a new commit

2) Skip this particular commit

  eg bisect skip    # Can't test the current version; give me a new commit

3) Abort

  eg bisect reset

See 'git help bisect' for more details."
}

sub refspecs {
  return "
Before reading up on refspecs, be sure you understand all the following
help pages:
  eg help merge
  eg help pull
  eg help push
  eg help rebase
  eg help remote
  eg help topic storage
refspecs compress knowledge from pieces of all those things into a short
amount of space.

refspecs are command line parameters to eg push or eg pull, used at the end
of the command line.  refspecs provide fine-grained control of pushing and
pulling changes in the following two areas:
  Since branches, tags, and remote tracking branches are all implemented by
  creating simple files consisting solely of a sha1sum, it is possible to
  push to or pull from different reference names and different reference
  types.

  Pushing and pulling of (possibly remote tracking) branches are typically
  accompanied by sanity checks to make sure the sha1sums on each end are
  related (to make sure that updates don't throw away previous commits, for
  example).  In some cases it is desirable to ignore such checks, such as
  when a branch has been rebased or commits have been amended.

The canonical format of a refspec is
  [+]SRC:DEST
That is, an optional plus character followed by a source reference, then a
colon character, then the destination reference.  There are a couple
special abbreviations, noted in the abbreviations section below.  The
meaning and syntax of the parts of a refspec are discussed next.

General source and destination handling
  Both the source and the destination reference are typically named by
  their path specification under the .git directory.  Examples:
    refs/heads/bob            # branch: bob
    refs/tags/v2.0            # tag: v2.0
    refs/remotes/jill/stable  # remote-tracking branch: jill/stable
  Leading directory paths can be omitted if no ambiguity would result.

  The refspec specifies that the push or pull operation should take the
  sha1sum from SRC in the source repository, and use it to fast-foward DEST
  in the destination repository.  The operation will fail if updating DEST
  would not be a fast-foward, unless the optional plus in the refspec is
  present.

  Pull operations are somewhat unusual.  For a pull, DEST is usually not
  the current branch.  In such cases, the current branch is also updated
  after DEST is.  The method of updating depends on whether --rebase was
  specified, and whether the latest revision of the current branch is an
  ancestor of the revision stored by DEST:
    If --rebase is specified:
      Rebase the current branch against DEST
    If --rebase is not specified, current branch is an ancestor of DEST:
      Fast-forward the current branch to DEST
    If --rebase is not specified, current branch is not an ancestor of DEST:
      Merge DEST into the current branch

Overriding push and pull sanity checks
  For both push and pull operations, the operation will fail if updating
  DEST to SRC is not a fast-forward.  This tends to happen in a few
  different circumstances:
    For pushes:
      * If someone else has pushed updates to the specified location
        already -- in such cases one should resolve the problem by doing a
        pull before attempting a push rather than overriding the safety
        check.
      * If one has rewritten history (e.g. using rebase, commit --amend,
        reset followed by subsequent commits)
    For pulls:
      * If one is pulling to a branch instead of a remote tracking branch
        -- in such a case, one should instead either specify a remote
        tracking branch for DEST or specify an empty DEST rather than
        overriding the safety check.
      * If one has somehow recorded commits directly to a remote tracking
        branch
      * If history has been rewritten on the remote end (e.g. by using
        rebase, commit --amend, reset followed by subsequent commits).
  In all such cases, users can choose to throw away any existing unique
  commits at the DEST end and make DEST record the same sha1sum as SRC, by
  using a plus character at the beginning of the refspec.

Abbreviations of refspecs
  Globbing syntax
    For either pushes or pulls, one can use a globbing syntax, such as
      refs/heads/*:refs/remotes/jim/*
    or
      refs/heads/*:refs/heads/*
    in order to specify pulling or pushing multiple locations at once.

  The following special abbreviations are allowed for both pushes and pulls:
    tag TAG
      This is equivalent to specifying refs/tags/TAG:refs/tags/TAG.

  The following special abbreviations are allowed for pushes:
    :REFERENCE
      This specifies delete the reference at the remote end (think of it as
      \"using nothing to update the remote reference\")

    REFERENCE
      This is the same as REFERENCE:REFERENCE

  The following special abbreviations are allowed for pulls:
    REFERENCE:
      This is used to merge REFERENCE into the current branch directly
      without storing the remote branch in some remote tracking branch.

    REFERENCE
      This is the same as REFERENCE: which is explained above.
";
}


sub remote_urls {
#
# NOTE: The help for remote_urls is basically lifted from the git manpages,
# which are licensed under GPLv2 (as is eg).
#
  return "
Any of the following notations can be used to name a remote repository:
  rsync://host.xz/path/to/repo.git/
  http://host.xz/path/to/repo.git/
  https://host.xz/path/to/repo.git/
  git://host.xz/path/to/repo.git/
  git://host.xz/~user/path/to/repo.git/
  ssh://[user@]host.xz[:port]/path/to/repo.git/
  ssh://[user@]host.xz/path/to/repo.git/
  ssh://[user@]host.xz/~user/path/to/repo.git/
  ssh://[user@]host.xz/~/path/to/repo.git
You can also use any of the following, which are identical to the last
three above, respectively
  [user@]host.xz:/path/to/repo.git/
  [user@]host.xz:~user/path/to/repo.git/
  [user@]host.xz:path/to/repo.git
Finally, you can also use the following notation to name a not-so-remote
repository:
  /path/to/repo.git/
  file:///path/to/repo.git/
These last two are identical other than that the latter disables some local
optimizations (such as hardlinking copies of history when cloning, in order
to save disk space).
";
}

sub revisions {
#
# NOTE: The pictoral example of revision suffixes is taken from the
# git-rev-parse manpage, which is licensed under GPLv2 (as is eg).
#
  return "
There are MANY different ways to refer to revisions (also referred to as
commits) of the repository.  Most are only needed for fine-grained control
in very large projects; the basics should be sufficient for most.

Basics
  The most common ways of referring to revisions (or commits), are:
    - Branch or tag name (e.g. stable, v0.77, master, 2.28branch, version-1-0)
    - Counting back from another revision (e.g. stable~1, stable~2, stable~3)
    - Cryptographic checksum (e.g. dae86e1950b1277e545cee180551750029cfe735)
    - Abbreviated checksum (e.g. dae86e)

  The output of 'eg log' shows (up to) two names for each revision: its
  cryptographic checksum and the count backward relative to the currently
  active branch (if the revision being shown in eg log is not part of the
  currently active branch then only the cryptographic checksum is shown).

  One can always check the validity of a revision name and what revision
  it refers to using 'eg log -1 REVISION' (the -1 to show only one revision).

Branches and Tags
  Users can specify a tag name to refer to the revision marked by that tag.
  Run 'eg tag' to get a list of existing tags.

  Users can specify a branch name to refer to the most recent revision of
  that branch.  Use 'eg branch' to get a list of existing branches.

Cryptographic checksums
  Each revision of a repository has an associated cryptographic checksum
  (in particular, a sha1sum) identifying it.  This cryptographic checksum
  is a sequence of 40 letters and numbers from 0-9 and a-f.  For example,
    dae86e1950b1277e545cee180551750029cfe735
  In addition to using these sha1sums to refer to revisions, one can also
  use an abbreviation of a sha1sum so long as enough characters are used to
  uniquely identify the revision (typically 6-8 characters are enough).

Special Names
  There are a few special revision names.

  Names that always exist:
    HEAD - A reference to the most recent revision of the current branch
           (thus HEAD refers to the same revision as using the branch
           name).  If there is no active branch, such as after running
           'eg switch TAG', then HEAD refers to the revision switched to.

           Note that the files in the working copy are always considered to
           be a (possibly modifed) copy of the revision pointed to by HEAD.

  Names that only exist in special cases:
    ORIG_HEAD -  Some operations (such as merge or reset) change which
                 revision the working copy is relative to.  These will
                 record the old value of HEAD in ORIG_HEAD.  This allows
                 one to undo such operations by running
                   eg reset --working-copy ORIG_HEAD
    FETCH_HEAD - When downloading branches from other repositories (via
                 the fetch or pull commands), the tip of the last fetched
                 branch is stored in FETCH_HEAD.
    MERGE_HEAD - If a merge operation results in conflicts, then the merge
                 will stop and wait for you to manually fix the conflicts.
                 In such a case, MERGE_HEAD will store the tip of the
                 branch(es) being merged into the current branch.  (The
                 current branch can be accessed, as always, through HEAD.)

Suffixes for counting backwards
  There are two suffixes for counting backwards from revisions to other
  revisions: ~ and ^.

  Adding ~N after a revision, with N a non-negative integer, means to count
  backwards N commits before the specified revision.  If any revision along
  the path has more than one parent (i.e. if any revision is a merge
  commit), then the first parent is always followed.  Thus, if stable is a
  branch, then
    stable   means the last revision on the stable branch
    stable~1 means one revision before the last on the stable branch
    stable~2 means two revisions before the last on the stable branch
    stable~3 means three revisions before the last on the stable branch
  In short, ~N goes back N generation of parents, always following the
  first parent.

  Adding ^N after a revision, with N a non-negative integer, means the Nth
  parent of the specified revision.  N can be omitted in which case it is
  assumed to have the value 1.  Thus, if stable is a branch, then
    stable   means the last revision on the stable branch
    stable^1 means the first parent of the last revision on the stable branch
    stable^2 means the second parent of the last revision on the stable branch
    stable^3 means the third parent of the last revision on the stable branch
  In short, ^N picks out one parent from the first generation of parents.

  Revisions with suffixes can themselves have suffixes, thus
    stable~5 = stable~3~2

  Here is an illustration with an unusually high amount of merging.  The
  illustration has 10 revisions each tagged with a different letter of the
  alphabet, with A referring to the most recent revision:
                A
               / \\
              /   \\
             B     C
            /|\\    |
           / | \\   |
          /  |  \\ /
         D   E   F
        / \\     / \\
       G   H   I   J

  From the illustration, the following equalities hold:
       A =      = A^0
       B = A^   = A^1     = A~1
       C = A^2  = A^2
       D = A^^  = A^1^1   = A~2
       E = B^2  = A^^2
       F = B^3  = A^^3
       G = A^^^ = A^1^1^1 = A~3
       H = D^2  = B^^2    = A^^^2  = A~2^2
       I = F^   = B^3^    = A^^3^
       J = F^2  = B^3^2   = A^^3^2

Revisions from logged branch tip history
  By default, all changes to each branch and to the special identifier HEAD
  are recorded in something called a reflog (short for \"reference log\",
  because calling it a \"branch log\" would not have made the glossary of
  special terms long enough).  Each entry of the reflog records the
  previous revision recorded by the branch, the new revision the branch was
  changed to, the command used to make the change (commit, merge, reset,
  pull, checkout, etc.), and when the change was made.  One can get an
  overview of the changes made to a branch (including the special branch
  'HEAD') by running
    eg reflog show BRANCHNAME

  One can make use of the reflog to refer to revisions that a branch used
  to point to.  The format for referring to revisions from the reflog are
    BRANCH\@{HISTORY_REFERENCE}
  Examples follow.

  Revisions that the branch pointed to, in order
    Assuming that ultra-bling is the name of a branch, the following can be
    used to refer to revisions ultra-bling used to point to:
      ultra-bling\@{0} is the same as ultra-bling
      ultra-bling\@{1} is the revision pointed to before the last change
      ultra-bling\@{2} is the revision ultra-bling pointed to two changes ago
      ultra-bling\@{3} is the revision ultra-bling pointed to three changes ago
    Note that any of these beyond the first could easily refer to commits
    that are no longer part of the ultra-bling branch (due to using a
    command like reset or commit --amend).

  Revisions that the branch pointed to at a previous time
    Assuing that fixes is the name of a branch, the following can be used to
    refer to revisions that fixes used to point to:
      fixes\@{yesterday}           - revision fixes pointed to yesterday
      fixes\@{1 day 3 hours ago}   - revision fixes pointed to 1 day 3 hours ago
      fixes\@{2008-02-29 12:34:00} - revision fixes had at 12:34 on Feb 29, 2008
    Again, these could refer to revisions that are no longer part of the
    fixes branch, 

  Using the branch log can be used to recover \"lost\" revisions that are
  no longer part of (or have never been part of) any branch reported by 'eg
  branch'.

Commit messages
  One can also refer a revision using the beginning of the commit message
  recorded in it.  This is done using with the two-character prefix :/
  followed by the beginning of the commit message.  Note that quotation marks
  are also often used to avoid having the shell split the commit message into
  different arguments.  Examples:
    :/\"Fix the biggest bug blocking the 1.0 release\"
    :/\"Make the translation from url\"
    :/\"Add a README file\"
  Note that if the commit message starts with an exclamation mark ('!'), then
  you need to type two of them; for example example:
    :/\"!!Commit messages starting with an exclamation mark are retarded\"

Other methods
  There are even more methods of referring to revisions.  Run \"man
  git-rev-parse\", and look for the \"SPECIFYING REVISIONS\" section for
  more details.
";
}

sub staging {
  return "
Marking changes from certain files as ready for commit allows you to split
your changes into two distinct sets (those that are ready for commit, and
those that aren't).  This includes support for limiting diffs to changes in
one of these two sets, and for committing just the changes that are ready.
It's a simple feature that comes in surprisingly handy:

  * When doing conflict resolution from large merges, hunks of changes can
    be categorized into known-to-be-good and still-needs-more-fixing
    subsets.

  * When reviewing a largish patch from someone else, hunks of changes can
    be categorized into known-to-be-good and still-needs-review subsets.

  * By staging your changes, you can go ahead and add temporary debugging
    code and have less fear of forgetting to remove it before committing --
    you will be warned about having both staged and unstaged changes at
    commit time, and you will have an easy way to locate the temporary
    code.

  * It makes it easier to keep \"dirty\" changes in your working copy for a
    long time without committing them.

Staging changes and working with staged changes
  Mark all changes in foo.py and baz.c as ready to be committed
    eg stage foo.py baz.c

  Selectively stage part of the changes
    eg stage -p
  (You will be asked whether to stage each change, listed in diff format;
  the main options to know are \"y\" for yes, \"n\" for no, and \"s\" for
  splitting the selected change into smaller changes; see 'git help add' for
  more details).

  Get all unstaged changes to bar.C and foo.pl
    eg diff --unstaged foo.pl bar.C

  Get all staged changes
    eg diff --staged

  Get all changes
    eg diff

  Revert the staged changes to bar.C, foo.pl and foo.py
    eg unstage bar.C foo.pl foo.py

  Commit just the staged changes
    eg commit --staged
";
}

sub storage {
  return "
Basics
  Each revision is referred to by a cryptographic checksum (in particular,
  a sha1sum) of its contents.  Each revision also knows which revision(s)
  it was derived from, known as the revision's parent(s).

  Each branch records the cryptographic checksum of the most recent commit
  for the branch.  Since each commit records its parent(s), a branch
  consists of its most recent commit plus all ancestors of that commit.
  When a new commit is made on a branch, the branch just replaces the
  cryptographic checksum of the old commit with the new one.

  Remote tracking branches, if used (see 'eg help remote'), differ from
  normal branches only in that they have a slash in their name.  For
  example, the remote tracking branch that tracks the contents of the
  stable branch of the remote named bob would be called bob/stable.  By
  their nature, remote tracking branches only track the contents of a
  branch of a remote repository; one does not switch to and commit to these
  branches.

  Tags simply record a single revision, much like branches, but tags are
  not advanced when additional commits are made.  Tags are not stored as
  part of a branch, though by default tags that point to commits which are
  downloaded (as part of merging changes from a branch) are themselves
  downloaded as well.

  Neither branches nor tags are revision controlled, though there is a log
  of changes made to each branch (known as a reflog, short for \"reference
  log\", because calling it a \"branch log\" wouldn't make the glossary of
  special terms long enough).

Pictorial explanation
  Using the letters A-P as shorthand for different revisions and their
  cryptographic checksums (which we'll assume were created in the order
  A...P for purposes of illustration), an example of the kind of structure
  built up by having commits track their parents is:
        N
        |
        M   P
        |   |
        L   O
        | \\ |
        J   K
        |   |
        H   I
        | /
        G
        |
        F
       / \\
      C   E
      |   |
      B   D
      |
      A
  In this picture, F has two parents (C and E) and is thus a merge commit.
  L is also a merge commit, having parents J and K.  There are two branches
  depicted here, which can be identified by N and P (due to the fact that
  branches simply track their most recent commit).  This history is
  somewhat unusual in that there is no unique start of history; instead
  there are two beginnings of history -- A and D.  Such a history can be
  created by pulling from, and merging with, a branch from another
  repository that shares no common history.  While unusual, it is fully
  supported.

  For further illustration, let's assume that the following branches exist:
      stable: N
      bling:  P
  Then the picture of each branch, side by side (using revision identifiers
  explained in 'eg help topic revisions'), is:
            stable
              |
           stable~1                                     bling
              |                                           |   
           stable~2                                    bling~1
              |   \\                                       |   
        stable~3  stable~2^2                           bling~2
              |     |                                     |   
        stable~4  stable~2^2~1                         bling~3
              |  /                                     /      
          stable~6                                bling~4     
              |                                     |         
          stable~7                                bling~5     
            /   \\                                 /   \\       
      stable~8  stable~7^2                   bling~6  bling~5^2
          |       |                             |       |     
      stable~9  stable~7^2~1                 bling~7  bling~5^2~1     
          |                                     |             
      stable~10                              bling~8             
  Note that there are many commits which are part of both branches,
  including two commits (I and K in the original picture) which were
  probably created after these two branches separated.  This is simply due
  to recording both parents in merge commits.

  Note that this tree-like or graph-like structure of branches is an
  example of something that computer scientists call a Directed Acyclic
  Graph (DAG); referring to it as such provides us the opportunity to
  make the glossary of special terminology longer.

Files and directories in a git repository (stuff under .git)
  You may find the following files and directories in your git repository.
  This document will discuss the highlights; see the repository-layout.html
  page distributed with git for more details.

  COMMIT_EDITMSG
    A leftover file from previous commits; this is the file that commit
    messages are recorded to when when you do not specify a -m or -F option
    to commit (thus causing an editor to be invoked).

  config
    A simple text file recording configuration options; see 'eg help config'.

  description
    A file that is only used by gitweb, currently.  If you use gitweb, this
    files provides a description of the project tracked in the repository.

  HEAD
  ORIG_HEAD
  FETCH_HEAD
  MERGE_HEAD
    See the Special Names section of 'eg help topic revisions'; these files
    record these special revisions.

  git-daemon-export-ok
    This file is only relevant if you are using git-daemon, a server to
    provide access to your repositories via the git:// protocol.
    git-daemon refuses to provide access to any repository that does not
    have a git-daemon-export-ok file.

  hooks
    A directory containing customizations scripts used by various commands.
    These scripts are only used if they are executable.

  index
    A binary file which records the staging area.  See 'eg help topic
    staging' for more information.

  info
    A directory with additional info about the repository

    info/exclude
      An additional place to specify ignored files.  Users typically use
      .gitignore files in the relevant directories to ignore files, but
      ignored files can also be listed here.

    info/ignored-unknown
      A list of unknown files known to exist previously, used to determine
      whether unknown files should cause commit (or push or publish) to
      abort.  See 'eg help commit' for more information; this list is
      updated whenever the -b flag is passed to commit.

    info/refs
      This is a file created by 'eg update-server-info' and is needed for
      repositories accessed over http.

  logs
    History of changes to references (i.e. to branches, tags, or
    remote-tracking branches).  The file logs/PATH/TO/FILE in the
    repository records the changes to the reference PATH/TO/FILE in the
    repository.  See also the 'Revisions from logged branch tip history'
    section of 'eg help topic revisions'.

  objects
    Storage of actual user data (files, directory trees, commit objects).
    Storage is done according to sha1sum of each object (splitting sha1sums
    into a combination of directory name and file name).  There are also
    packs, which compress many objects into one file for tighter storage
    and reduced disk usage.

  packed-refs
    The combination of paths, filenames, and sha1sums from many different
    refs -- one per line; see refs below.

  refs
    Storage of references (branches, heads, or remote tracking branches).
    Each reference is a simple file consisting of a sha1sum (see 'eg help
    topic storage' for more information).  The path provides the type of
    the reference, the file name provides the name for the reference, and
    the sha1sum is the revision the reference refers to.

    Branches are stored under refs/heads/*, tags under refs/tags/*, and
    remote tracking branches under refs/remotes/REMOTENAME/*.  Note that
    some of these references may appear in packed-refs instead of having
    a file somewhere under the refs directory.
";
}

sub help {
  my $self = shift;
  my $help_msg;

  # Get the topic we want more info on (replace dashes, since they can't
  # be in function names)
  my $topic = shift @ARGV;
  my $orig_topic = $topic;
  $topic =~ s/-/_/g if $topic;

  ### FIXME: Add the following topics, plus maybe some others
  # glossary      <Not yet written; this is just a stub>

  my $topics = "
middle-of-am      How to resolve or abort an incomplete am (apply mail)
middle-of-bisect  How to continue or abort a bisection
middle-of-merge   How to resolve or abort an incomplete merge
middle-of-rebase  How to resolve or abort an incomplete rebase

refspecs      Advanced pushing and pulling: detailed control of storage
remote-urls   Format for referring to remote (and not-so-remote) repositories
revisions     Various methods for referring to revisions
staging       Marking a subset of the local changes ready for committing
storage       High level overview of how commits, tags, and branches are stored
";

  if (defined $topic) {
    die "No topic help for '$topic' exists.  Try 'eg help topic'.\n"
      if !$self->can($topic);
    $help_msg = $self->$topic();
    if ($topics =~ m#^(\Q$orig_topic\E.*)#m) {
      $topic = $1;
    }
  } else {
    $topic = "Topics";
    $help_msg = $topics;
  }

  $ENV{"LESS"} = "FRSX" unless defined $ENV{"LESS"};
  my $less = ($USE_PAGER == 1) ? "less" :
             ($USE_PAGER == 0) ? "cat" :
             `$GIT_CMD config core.pager` || "less";
  chomp($less);
  open(OUTPUT, "| $less");
  print OUTPUT "$topic\n";
  print OUTPUT $help_msg;
  close(OUTPUT);

  exit 0;
}

###########################################################################
# info                                                                    #
###########################################################################
package info;
@info::ISA = qw(subcommand);
INIT {
  $COMMAND{info} = {
    new_command => 1,
    section => 'discovery',
    extra => 1,
    about => 'Show some basic information about the current repository'
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(git_equivalent => '', git_repo_needed => 0, @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg info [/PATH/TO/REPOSITORY]

Description:
  Shows information about the specified repository, or the current
  repository if none is specified.

  Most of the output of eg info is self-explanatory, but some fields
  benefit from extra explanation or pointers about where to find related
  information.  These fields are:

    Total commits
      The total number of commits (or revisions) found in the repository.
      eg log can be used to view revision authors, dates, and commit log
      messages.

    Local repository
      eg has a number of files and directories it uses to track your data,
      including (by default) a copy of the entire history of the project.
      These files and directories are all stored below a single directory,
      referred to as the local repository.  See 'eg help topic storage' for
      more details.

    Named remote repositories
      To make it easier to track changes from multiple remote repositories,
      eg provides the ability to provide nicknames for and work with
      multiple branches from a remote repository and even working with
      multiple remote repositories at once.  See 'eg help remote' for more
      details, though you will want to make sure you understand 'eg help
      pull' and 'eg help push' first.

    Current branch
      All development is done on a branch, though smaller projects may only
      use one branch per repository (thus making the repository effectively
      serve as a branch).  In contrast to cvs and svn which refer to
      mainline development as \"HEAD\" and \"TRUNK\", respectively, eg
      calls the mainline development a branch as well, with the default
      name of \"master\").  See 'eg help branch' and 'eg help topic
      storage' for more details.

    Cryptographic checksum
      Each revision has an associated cryptographic checksum of both its
      contents and the revision(s) it was derived from, providing strong
      data consistency checks and guarantees.  These checksums are shown in
      the output of eg log, and serve as a way to refer to revisions.  See
      also 'eg help topic storage' for more details.

    Default pull/push configuration options:
      The default repository to push to or pull from defaults to 'origin',
      if the 'origin' remote has been set up (see 'eg help remote' for
      setting up remote repository nicknames).

      However, the default repository can be set on a per-branch basis as a
      configuration option (see 'eg help config').  In fact, a number of
      default pull/push actions can be set as per-branch configuration
      options: default merge options to use on a given branch, default
      branch to merge with from the remote repository, and whether to
      rebase (rewrite local commits on top of new remote commits; see 'eg
      help rebase') rather than merge (keep local commits as they are and
      just make a merge commit combining local and remote changes; see 'eg
      help merge').

";
  $self->{'differences'} = '
  eg info is unique to eg; git does not have a similar command.  It
  originally was intended just to do something nice if svn converts happen
  to try this command, but I have found it to be a really nice way of
  helping users get their bearings.  It also provides some nice statistics
  that git users may appreciate (particularly when it comes time to fill
  out the Git User Survey).
';
  return $self;
}

sub preprocess {
  my $self = shift;

  my $path = shift @ARGV;
  die "Aborting: Too many arguments to eg info.\n" if @ARGV;

  if ($path) {
    die "$path does not look like a directory.\n" if ! -d $path;
    my ($ret, $useless_output) =
      ExecUtil::execute_captured("$GIT_CMD ls-remote $path", ignore_ret => 1);
    if ($ret != 0) {
      die "$path does not appear to be a git archive " .
          "(maybe it has no commits yet?).\n";
    }
    chdir($path);
  }

  # Set git_dir
  $self->{git_dir} = RepoUtil::git_dir();
  die "Must be run inside a git repository!\n" if !defined $self->{git_dir};
}

sub run {
  my $self=shift;

  my $branch = RepoUtil::current_branch();

  #
  # Special case the situation of no commits being present
  #
  if (RepoUtil::initial_commit()) {
    if ($DEBUG < 2) {
      print STDERR <<EOF;
Total commits: 0
Local repository: $self->{git_dir}
There are no commits in this repository.  Please use eg stage to mark new
files as being ready to commit, and eg commit to commit them.
EOF
    }
    exit 1;
  }

  #
  # Repository-global information
  #

  # total commits
  my $total_commits = ExecUtil::output("$GIT_CMD rev-list --all | wc -l");
  print "Total commits: $total_commits\n" if $DEBUG < 2;

  # local repo
  print "Local repository: $self->{git_dir}\n" if $DEBUG < 2;

  # named remote repos
  my %remotes;
  my $longest = 0;
  my @abbrev_remotes = split('\n', ExecUtil::output("$GIT_CMD remote"));
  foreach my $remote (@abbrev_remotes) {
    chomp($remote);
    my $url = RepoUtil::get_config("remote.$remote.url");
    $remotes{$remote} = $url;
    $longest = main::max($longest, length($remote));
  }
  if (scalar keys %remotes > 0 && $DEBUG < 2) {
    print "Named remote repositories: (name -> location)\n";
    foreach my $remote (sort keys %remotes) {
      printf "  %${longest}s -> %s\n", $remote, $remotes{$remote};
    }
  }

  #
  # Stats for the current branch...
  #
  return if !defined($branch);

  # File & directory stats only work if we're in the toplevel directory
  my ($orig_dir, $top_dir, $git_dir) = RepoUtil::get_dirs();
  chdir($top_dir);

  # Name
  print "Current branch: $branch\n" if $DEBUG < 2;

  # Sha1sum
  my $current_commit = ExecUtil::output("$GIT_CMD show-ref -s -h | head -n 1");
  print "  Cryptographic checksum (sha1sum): $current_commit\n" if $DEBUG < 2;

  # Default pull/push options
  my $default = "-None-";
  my $print_config_options = 0;
  my ($ret, $options) =
    ExecUtil::execute_captured("$GIT_CMD config --get-regexp " .
                               "^branch\.$branch\.*", ignore_ret => 1);
  chomp($options);
  my @lines;
  if ($ret == 0) {
    @lines = split('\n', $options);
    my $line_count = scalar(@lines);
    $print_config_options = ($line_count > 0);

    if ($options =~ /^branch\.$branch\.remote (.*)$/m) {
      $default = $1;
      $print_config_options = ($line_count > 1);
    } else {
      my @output = `$GIT_CMD config --get-regexp remote.origin.*`;
      $default = "origin" if @output;
    }
  }
  print "  Default pull/push repository: $default\n" if $DEBUG < 2;
  if ($print_config_options && $DEBUG < 2) {
    print "  Default pull/push options:\n";
    foreach my $line (@lines) {
      $line =~ s/\s+/ = /;
      print "    $line\n";
    }
  }

  # No. contributors
  my $contributors  = ExecUtil::output("$GIT_CMD shortlog -s -n HEAD | wc -l");
  print "  Number of contributors: $contributors\n" if $DEBUG < 2;

  # No. files
  my $num_files = ExecUtil::output("$GIT_CMD ls-tree -r HEAD | wc -l");
  print "  Number of files: $num_files\n" if $DEBUG < 2;

  # No. dirs
  my $num_dirs = ExecUtil::output(
                    "$GIT_CMD ls-tree -r -t HEAD " .
                    " | grep -E '[0-9]+ tree'" .
                    " | wc -l");
  print "  Number of directories: $num_dirs\n" if $DEBUG < 2;

  # Some ugly, nasty code to get the biggest file.  Seems to be the only
  # method I could find that would work given the corner case filenames
  # (spaces and unicode chars) in the git.git repo (Try eg info on repo
  # from 'git clone git://git.kernel.org/pub/scm/git/git.git').
  my @files = `$GIT_CMD ls-tree -r -l --full-name HEAD`;
  my %biggest = (name => '', size => 0);
  foreach my $line (@files) {
    if ($line =~ m#^[0-9]+ [a-z]+ [0-9a-f]+[ ]*(\d+)[ \t]*(.*)$#) {
      my ($size, $file) = ($1, $2);
      if ($file =~ m#^\".*\"#) { $file = eval "$file" };  # Unicode fix
      if ($size >= $biggest{size}) {
        $biggest{name} = $file;
        $biggest{size} = $size;
      }
    }
  }
  my $biggest_file = "$biggest{size} ($biggest{name})";
  print "  Biggest file size, in bytes: $biggest_file\n" if $DEBUG < 2;

  # No. commits
  my $branch_depth  = ExecUtil::output("$GIT_CMD rev-list HEAD | wc -l");
  print "  Commits: $branch_depth\n" if $DEBUG < 2;

  # Other possibilities:
  #   Disk space used by respository (du -hs .git, or packfile size?)
  #   Disk space used by working copy (???)
  #   Number of unpacked objects?

  chdir($orig_dir);

  # Well, if we got this far, it must have worked, so...
  return 0;
}

###########################################################################
# init                                                                    #
###########################################################################
package init;
@init::ISA = qw(subcommand);
INIT {
  $COMMAND{init} = {
    unmodified_behavior => 1,
    section => 'creation',
    about => 'Create a new repository'
  };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(git_repo_needed => 0, @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg init [--shared]

Description:
  Creates a new repository.

  If you want to publish a copy of an existing repository so that others
  can access it, use 'eg publish' instead.

  Note for cvs/svn users: With cvs or svn it is common to create an empty
  repository on \"the server\", then check it out locally and start adding
  files and committing.  With eg, it is more natural to create a repository
  on your local machine and start creating and adding files, then later
  (possibly as soon as one commit later) publishing your work to \"the
  server\".  git (and thus eg) does not currently allow cloning empty
  repositories, so for now you must change habits.

Examples:
  Create a new blank repository, then use it by creating and adding a file
  to it:
      \$ mkdir project
      \$ cd project
      \$ eg init
      Create and edit a file called foo.py
      \$ eg stage foo.py
      \$ eg commit

  Create a repository to track further changes to an existing project.  Then
  start using it right away
      \$ cd cool-program
      \$ eg init
      \$ eg stage .           # Recursively adds all files
      \$ eg commit -m \"Initial import of all files\"
      Make more changes to fix a bug or add a new feature or...
      \$ eg commit

  (Advanced) Create a new blank repository meant to be used in a
  centralized fashion, i.e. a repository for many users to commit to.
      \$ mkdir new-project
      \$ cd new-project
      \$ eg init --shared
      Check repository ownership and user groups to ensure they are right

Options:
  --shared
    Set up a repository that will shared amongst several users; note that
    you are responsible for creating a common group for developers so that
    they can all write to the repository.  Ask your sysadmin or see the
    groupadd(8), usermod(8), chgrp(1), and chmod(1) manpages.
";
  return $self;
}

###########################################################################
# log                                                                     #
###########################################################################
package log;
@log::ISA = qw(subcommand);
INIT {
  $COMMAND{log} = {
    section => 'discovery',
    about => 'Show history of recorded changes'
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(
    git_repo_needed => 1,
    @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg log

Description:
  Shows a history of recorded changes.  Displays commit identifiers,
  the authors of the changes, and commit messages.
";
  $self->{'differences'} = '
  eg log output differs from git log output by showing simpler revision
  identifiers that will be easier for new users to understand and use.
  In detail:
    eg log
  is essentially the same as
    git log | git name-rev --stdin --refs=$(git symbolic-ref HEAD) | less
  However, it implements the name-rev behavior internally to provide
  incremental history processing (which avoids slow upfront full-history
  analyses) in common cases.
';
  return $self;
}

sub _get_values ($$) {
  my ($names, $sha1sum) = @_;
  my ($name, $distance);
  if (defined($names->{$sha1sum})) {
    ($name, $distance) = @{$names->{$sha1sum}};
  }
  return ($name, $distance);
}

sub _path_count ($) {
  my ($name) = @_;
  my @matches = ($name =~ m/[~^]/g);
  return scalar @matches;
}

sub _get_revision_name ($$$) {
  my ($sha1sum, $filehandle, $names) = @_;
  my ($name, $distance);

  # If we've already determined teh name of this sha1sum before, just return it
  ($name, $distance) = _get_values($names, $sha1sum);
  return $name if defined $name;

  # Loop over rev-list output, naming the parents of each commit as we walk
  # backward in history (breaking whenever if we hit our sha1sum)
  while (<$filehandle>) {
    # Each line of the rev-list output is of form
    #   sha1sum-of-commit sha1sum-of-parent1 sha1sum-of-parent2...
    my ($child, $parent, @merge_parents) = split;

    next if !$parent;

    # Determine the name of the current commit, and its distance from the head
    # of the current branch
    my ($cur_name, $distance) = _get_values($names, $child);
    die "Yikes!  Your history is b0rken!\n" if (!$cur_name);

    # Determine any name we previously determined for $parent, the name we
    # would give it relative to $child, and determine which should "win"
    my ($orig_parent_name, $orig_parent_distance) = _get_values($names, $parent);
    my $parent_name;
    if ($cur_name =~ /^(.*)~(\d+)$/) {
      my $count = $2 + 1;
      $parent_name = "$1~$count";
    } else {
      $parent_name = "$cur_name~1";
    }
    my $parent_distance = $distance + 1;
    if (!$orig_parent_name ||
        _path_count($orig_parent_name) > _path_count($parent_name)) {
      $names->{$parent} = [$parent_name, $parent_distance];
    }

    # Do the same for other parents, though their naming scheme is slightly
    # different
    my $count=2;
    foreach my $merge_parent (@merge_parents) {
      ($orig_parent_name, $orig_parent_distance) =
        _get_values($names, $merge_parent);
      if (!$orig_parent_name ||
          _path_count($orig_parent_name) > _path_count("$cur_name^$count")) {
        $names->{$merge_parent} = ["$cur_name^$count", $parent_distance];
      }
      $count++;
    }

    # Check if we found the needed sha1sum, and exit early if so
    push(@merge_parents, $parent);
    last if (grep {$_ eq $sha1sum} @merge_parents);
  }

  # Check if we found the needed sha1sum; if so, return it
  ($name, $distance) = _get_values($names, $sha1sum);
  return $name if $name;

  # We didn't find the wanted sha1sum; it has no name relative to the current
  # branch using tildes and hats.
  return "";
}

sub run {
  my $self = shift;
  @ARGV = Util::quote_args(@ARGV);

  my $branch = RepoUtil::current_branch();

  # Check whether to warn if there are no commits.  We don't want to parse
  # all the arguments to determine if there is a valid revision listed on the
  # command line (or, failing that, whether HEAD reference a valid revision);
  # instead, we just check for the simple case of no branches existing yet.
  if (!`$GIT_CMD branch -a`) {
    die "Error: No recorded commits to show yet.\n";
  }

  # We can just run plain git log if there's not current branch
  if (!$branch || !RepoUtil::valid_ref($branch)) {
    return ExecUtil::execute("$GIT_CMD log @ARGV", ignore_ret => 1);
  }

  my ($ret, $revision) =
    ExecUtil::execute_captured("$GIT_CMD rev-parse refs/heads/$branch");
  exit $ret if $ret;
  chomp($revision);

  # Show the user the essential equivalent to what we manually do
  if ($DEBUG) {
    print "    >>Running: $GIT_CMD log @ARGV | \\\n" .
       "               $GIT_CMD name-rev --stdin " .
           "--refs=refs/heads/$branch | \\\n" .
       "               less\n";
    return 0 if $DEBUG == 2;
  }

  # Setup name determination via output from git rev-list
  my %names;
  open(REV_LIST_INPUT, "$GIT_CMD rev-list --parents $branch -- | ");
  $names{$revision} = [$branch, 0];

  # Loop over the output of git log, printing/modifying as we go
  my $use_colors = -t STDOUT ? "GIT_PAGER_IN_USE=1" : "";
  open(INPUT, "$use_colors $GIT_CMD log @ARGV | ");
  $ENV{"LESS"} = "FRSX" unless defined $ENV{"LESS"};
  my $less = ($USE_PAGER == 1) ? "less" :
             ($USE_PAGER == 0) ? "cat" :
             `$GIT_CMD config core.pager` || "less";
  chomp($less);
  my $pid = open(OUTPUT, "| $less");

  # Make sure that we don't leave the terminal in a weird state if the user
  # hits Ctrl-C during eg log
  local $SIG{INT} = 
    sub { kill 'SIGKILL', $pid; close(INPUT); close(OUTPUT); close(REV_LIST_INPUT);
          exit(0); };
 
  #open(OUTPUT, ">&STDOUT");
  while (<INPUT>) {
    # If it's a commit line, determine the name of the commit and print it too
    # ANSI color escape sequences make this regex kind of ugly...
    if (/^((?:\e\[.*?m)?commit ([0-9a-f]{40}))((?:\e\[m)?)$/) {
      my $name = _get_revision_name($2, *REV_LIST_INPUT, \%names);
      print OUTPUT "$1 ($name)$3\n" if $name;
      print OUTPUT "$1$3\n"         if !$name;
    } else {
      print OUTPUT;
    }
  }
  my ($ret1, $ret2, $ret3);
  close(INPUT);  $ret1 = $? >> 8;
  close(OUTPUT); $ret2 = $? >> 8;

  # Make sure we close the pipe from rev-list too; We use "$? && $!"
  # instead of "$?" because we don't care about the return value of the
  # rev-list program -- which we prematurely close -- just whether the close
  # succeeded.  We can't just use "$!" because if --pretty="format:%s" is
  # passed to eg log, then $! will be "Bad file descriptor" which translates
  # to a nonzero exit status.
  # (This is my best guess at what to do given the random failures from
  # t1411-reflog-show.sh, and reading 'man perlfunc' under 'close'; it seems
  # to work.)
  close(REV_LIST_INPUT);  $ret3 = ($? >> 8) && $!;

  return $ret1 || $ret2 || $ret3;
}

###########################################################################
# merge                                                                   #
###########################################################################
package merge;
@merge::ISA = qw(subcommand);
INIT {
  $COMMAND{merge} = {
    unmodified_behavior => 1,
    section => 'projects',
    about => 'Join two or more development histories (branches) together'
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(git_repo_needed => 1, @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg merge [-m MESSAGE] BRANCH...

Description:
  Merges another branch (or more than one branch) into the current branch.

  You may want to skip to the examples; the remainder of this description
  section just has boring details about how merges work.

  There are three different ways to handle merges depending on whether the
  current branch or the specified merge branches have commits not found in
  the other.  These cases are:
    1) The current branch contains all commits in the specified branch(es).
         In this case, there is nothing to do.
    2) Both the current branch and the specified merge branch(es) contain
       commits not found in the other:
         In this case, a new commit will be created which (a) includes
         changes from both the current branch and the merge branch(es) and
         (b) records the parents of the new commit as the last revision of
         the current branch and the last revision(s) of the merge
         branch(es).
    3) The specified merge branch has all the commits found in the current
       branch.
         In this case, a new commit is not needed to merge the branches
         together.  Instead, the current branch simply changes the record
         of its last revision to that of the specified merge branch.  This
         is known as a fast-forward update.
  See 'eg help topic storage' for more information.

Examples:
  Merge all changes from the stable branch that are not already in the
  current branch, into the current branch.
      \$ eg merge stable

  Merge all changes from the refactor branch into the current branch (i.e.
  same as the previous example but merging in a different branch)
      \$ eg merge refactor

Options:
  -m MESSAGE
    Use MESSAGE as the commit message for the created merge commit, if
    a merge commit is needed.
";
  return $self;
}

###########################################################################
# publish                                                                 #
###########################################################################
package publish;
@publish::ISA = qw(subcommand);
INIT {
  $COMMAND{publish} = {
    extra => 1,
    new_command => 1,
    section => 'collaboration',
    about => 'Publish a copy of the current repository on a remote machine'
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(
    git_repo_needed => 1,
    git_equivalent => '',
    initial_commit_error_msg => "Error: No recorded commits to publish.",
    @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg publish [-b|--bypass-modification-check] [-g|--group GROUP]
             [REMOTE_ALIAS] SSH_URL

Description:
  Publishes a copy of the current repository on a remote machine.  Note
  that local changes will be ignored; only committed changes will be
  published.  You must have ssh access to the remote machine and must have
  both git and ssh installed on both local and remote machines.

  After publishing the repository, it is accessible via the remote
  REMOTE_ALIAS, thus allowing you to use REMOTE_ALIAS to push and pull
  commands.  If REMOTE_ALIAS is not specified, it defaults to 'origin'.

  If the --group (or -g) option is specified, the given GROUP must be a
  valid unix group on the remote machine, and the user must be a member of
  that group.  When this option is passed, eg publish will ensure that all
  files are readable and writable by members of that group.

  Note that the remote location is specified using a ssh url; see 'eg help
  topic remote_urls' for a full list of valid possibilities, but the
  general case is to use scp(1) syntax: [[USER@]MACHINE]:REMOTE_PATH.  Note
  that if any files or directories exist below the specified remote
  directory, publish will abort.

Examples:
  Publish a copy of the current repository on the machine myserver.com in
  the directory /var/scratch/git-stuff/my-repo.git, and make it readable
  and writable by the unix group 'gitters'.  Then immediately make a clone
  of the remote repository
      \$ eg publish -g gitters myserver.com:/var/scratch/git-stuff/my-repo.git
      \$ cd ..
      \$ eg clone myserver.com:/var/scratch/git-stuff/my-repo.git

  Publish a copy of the current repository on the machine www.gnome.org, in
  the public_html/myproj subdirectory of the home directory of the remote
  user fake, then immediately clone it again into a separate directory
  named another-myproj.
      \$ eg publish fake\@www.gnome.org:public_html/myproj
      \$ cd ..
      \$ eg clone http://www.gnome.org/~fake/myproj another-myproj

Options
  --bypass-modification-check, -b
    To prevent you from publishing an incomplete set of changes, publish
    typically checks whether you have new unknown files or modified files
    present and aborts if so.  You can bypass these checks with this
    option.
";
  $self->{'differences'} = '
  eg publish is unique to eg, designed to condense the multiple necessary
  steps with git into one (or a few) commands.  The steps that eg publish
  performs are essentially:
      if ( git config --get remote.REMOTE_ALIAS.url > /dev/null); then
        echo "REMOTE_ALIAS already defined"; false;
      fi &&
      ssh [USER@]MACHINE "
        test -d REMOTE_PATH && echo "REMOTE_PATH already exists!" && exit 1;
        if (! groups | grep "\bGROUP\b" > /dev/null); then
          echo "Cannot change to group GROUP";  exit 1;
        fi;
        if (! type -p git>/dev/null);then echo "Cannot find git"; exit 1; fi &&
        newgrp GROUP;
        mkdir -p REMOTE_PATH &&
        cd REMOTE_PATH &&
        git init [--shared] --bare &&
        touch git-daemon-export-ok &&
        (mv hooks/post-update.sample hooks/post-update || true) &&
        chmod u+x hooks/post-update" &&
      git remote add REMOTE_ALIAS [USER@]MACHINE:REMOTE_PATH &&
      git push
  Note that the command involving git-daemon-export-ok is only needed if
  you will be cloning/pulling from the repository via the git:// protocol
  (in which case you are responsible for running git-daemon on the remote
  machine), and the post-update hook related stuff is only necessary if you
  are trying to clone/pull via the http:// protocol (in which case you are
  responsible for running a webserver such as httpd on the remote machine);
  neither of these steps are needed if you are cloning/pulling via ssh, but
  they do not cause problems either.

  MULTI-USER NOTE: If you want multiple people to be able to push to the
  resulting repository, you will need to ensure that they all have ssh
  access to the machine, that they are all part of the same unix group, and
  that you use the --group option to ensure that the repository is set up
  to be shared by the relevant group.
';
  return $self;
}

sub preprocess {
  my $self = shift;
  my $package_name = ref($self);

  my $bypass_modification_check = 0;
  my $group;
  my $result = main::GetOptions(
    "--help"           => sub { $self->help() },
    "bypass-modification-check|b" => \$bypass_modification_check,
    "group|g=s"                   => \$group,
    );

  die "Aborting: Need a URL to push to!\n" if @ARGV < 1;
  die "Aborting: Too many args to eg publish: @ARGV\n" if @ARGV > 2;
  my $extra_info = (@ARGV == 2) ? "" : ", please specify a REMOTE_ALIAS";
  $self->{remote} = (@ARGV == 2) ? shift @ARGV : "origin";
  $self->{repository} = shift @ARGV;
  $self->{group} = $group;

  die "Aborting: remote '$self->{remote}' already exists$extra_info!\n"
    if RepoUtil::get_config("remote.$self->{remote}.url");

  if (!$bypass_modification_check) {
    my $status = RepoUtil::commit_push_checks($package_name,
                                              {unknown => 1,
                                               changes => 1,
                                               unmerged_changes => 1});
  } else {
    # Record the set of unknown files we ignored with -b, so the -b flag
    # isn't needed next time.
    RepoUtil::record_ignored_unknowns();
  }
}

sub run {
  my $self = shift;

  my ($user, $machine, $port, $path) =
    Util::split_ssh_repository($self->{repository});
  if (!defined $path) {
    # It may be a local path rather than an ssh path...
    if ($self->{repository} =~ m#^/[^:]*#) {
      $path = $self->{repository};
    } else {
      die "Aborting: Could not parse remote repository URL " .
          "'$self->{repository}'.\n";
    }
  }

  my ($sg, $sge, $check_group, $shared) = ("", "", "", "");
  if (defined $self->{group}) {
    $check_group = "
        if (! groups | grep '\\b$self->{group}\\b' > /dev/null); then
          echo 'Cannot change to group $self->{group}!'; exit 1;
        fi;";
    $sg = "sg $self->{group} -c '";
    $sge = "'";
    $shared = "--shared ";
  }

  my $ret;
  if (defined $machine) {
    print "Setting up remote repository via ssh...\n";
    $ret = ExecUtil::execute("
      ssh $port -q $user$machine \"
        test -d $path && echo '$path already exists!' && exit 1; $check_group
        if (! type -p git>/dev/null);then echo 'Cannot find git'; exit 1; fi;
        ${sg}mkdir -p $path${sge} &&
        cd $path &&
        ${sg}git init ${shared}--bare${sge} &&
        touch git-daemon-export-ok &&
        (mv hooks/post-update.sample hooks/post-update || true) &&
        chmod u+x hooks/post-update\"",
      ignore_ret => 1);
  } else {
    print "Setting up not-so-remote repository...\n";
    $ret = ExecUtil::execute("
        test -d $path && echo '$path already exists!' && exit 1; $check_group
        if (! type -p git>/dev/null);then echo 'Cannot find git'; exit 1; fi;
        ${sg}mkdir -p $path${sge} &&
        cd $path &&
        ${sg}$GIT_CMD init ${shared}--bare${sge} &&
        touch git-daemon-export-ok &&
        (mv hooks/post-update.sample hooks/post-update || true) &&
        chmod u+x hooks/post-update",
      ignore_ret => 1);
  }
  die "Remote repository setup failed!\n" if $ret != 0;

  print "Creating new remote $self->{remote}...\n";
  #if ($self->{remote} ne "origin") {
  #  print "If $self->{remote} should be a default push/pull location, run:\n" .
  #        "   eg track [LOCAL_BRANCH] $self->{remote}/REMOTE_BRANCH\n";
  #}
  ExecUtil::execute("$GIT_CMD remote add $self->{remote} $self->{repository}");
  print "Pushing to new remote $self->{remote}...\n";
  $ret = ExecUtil::execute("$GIT_CMD push --mirror $self->{remote}");
  if ($ret) {
    ExecUtil::execute("$GIT_CMD remote rm $self->{remote}");
    return $ret;
  }

  print "Done.\n";

  return 0;
}

###########################################################################
# pull                                                                    #
###########################################################################
package pull;
@pull::ISA = qw(subcommand);
INIT {
  $COMMAND{pull} = {
    section => 'collaboration',
    about => 'Get updates from another repository and merge them'
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(git_repo_needed => 1, @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg pull [--branch BRANCH] [--no-tags] [--all-tags] [--tag TAG]
          [--no-commit] [--rebase] REPOSITORY

Description:
  Pull changes from another repository and merge them into the local
  repository.  If there are no conflicts, the result will be committed.

  See 'eg help topic remote-urls' for valid syntax for remote repositories.
  If you frequently pull from the same repository, you may want to set up a
  nickname for it (see 'eg help remote'), so that you can specify the
  nickname instead of the full repository URL every time.  If you want to
  set a (different) default repository and branch to pull from, see 'eg
  track'.

  By default, tags in the remote repository associated with commits that
  are pulled, will themselves be pulled.  One can specify to pull
  additional or fewer tags with the --all-tags, --no-tags, or --tag TAG
  options.

  If there is more than one branch (on either end):
    If the local repository has more than one branch, the changes are
    always merged into the active branch (use 'eg info' or 'eg branch' to
    determine the active branch).

    If you do not specify which remote branch to pull, and you have not
    previously pulled a remote branch from the given repository, then eg
    will abort and ask you to specify a remote branch (giving you a list to
    choose from).

  Note for users of named remote repositories and remote tracking branches:
    If you set up named remote repositories (using 'eg remote'), you can
    make 'eg pull' obtain changes from several branches at once.  In such a
    case, eg will take the changes and record them in special local
    branches known as \"remote tracking branches\", a step which involves
    no merging.  Most of these branches will not be handled further after
    this step.  eg will then take changes from just the branch(es)
    specified (with the --branch option, or with the
    branch.CURRENTBRANCH.merge configuration variable, or by the last
    branch(es) merged), and merge it/them into the active branch.

    The advantage of pulling changes from branches that you do not
    immediately merge with is that you can then later inspect, review, or
    merge with such changes (using 'eg merge') even if not connected to the
    network.  Naming the remote repositories also allows you to use the
    shorter name instead of the full location of the repository.  (eg
    remote also provides the ability to update from groups of remote
    repositories simultaneously.)  See 'eg help remote' and 'eg help topic
    storage' for more information about named remote repositories and
    remote tracking branches.

Examples:
  Pull changes from myserver.com:git-stuff/my-repo.git
      \$ eg pull myserver.com:git-stuff/my-repo.git

  Pull changes from the stable branch of git://git.foo.org/whizbang into the
  active local branch
      \$ eg pull --branch stable git://git.foo.org/whizbang

  Pull changes from the debug branch in the remote repository nicknamed
  'carl' (see 'eg help remote' for more information about nicknames for
  remote repositories)
      \$ eg pull --branch debug carl

  Pull changes from a remote repository that has multiple branches
      Hmm, we don't know which branches the remote repository has.  Just
      try it.
      \$ eg pull ssh://machine.fake.gov/~user/hack.git
      That gave us an error telling us it didn't know which branch to pull
      from, but it told us that there were 3 branches: 'master', 'stable',
      and 'nasty-hack'.  Let's get changes from the nasty-hack branch!
      \$ eg pull --branch nasty-hack ssh://machine.fake.gov/~user/hack.git

Options
  --branch BRANCH
    Merge the changes from the remote branch BRANCH.  May be used multiple
    times to merge changes from multiple remote branches at once.

  --no-tags
    Do not download any tags from the remote repository

  --all-tags
    Download all tags from the remote repository.

  --tag TAG
    Download TAG from the remote repository

  --no-commit
    Perform the merge but do not commit even if the merge is clean.

  --rebase
    Instead of a merge, perform a rebase; in other words rewrite commit
    history so that your recent local commits become commits on top of the
    changes downloaded from the remote repository.

    NOTE: This is a potentially dangerous operation if you have local
    commits not found in the repository you are pulling from but which are
    found in some other repository (e.g. your local commits have been
    directly pulled from your copy by another developer, or to your copy
    from another developer).  In such a case, unless the other copy of
    these commits are also rebased (or discarded), you will probably get
    into trouble and need to thoroughly understand 'eg help rebase' before
    using this option.
";
  $self->{'differences'} = "
  eg pull and git pull are nearly identical.  eg provides a slightly more
  meaningful name for --tags (\"--all-tags\"), introduces a new option
  named --branch, and tries to assist the user when no branch to
  merge/rebase is specified on the command line or in the config.

  The new --branch option (1) avoids the need to explain refspecs too early
  to users, (2) makes command line examples more self-documenting.  eg
  still accepts refspecs at the end of the commandline the same as git
  pull, however their explanation is deferred to 'eg help topic refspecs'.

  When no branch to merge/rebase is specified, eg pull will provide a list
  of known branches at the remote end.  In the special case that the remote
  has exactly one branch, eg will use that branch for merging/rebasing
  rather than erroring out.
";
  return $self;
}

sub preprocess {
  my $self = shift;

  #
  # Parse options
  #
  $self->{args} = [];
  my $record_arg  = 
    sub { my $prefix = "";
          $prefix = "no-" if defined $_[1] && $_[1] == 0;
          push(@{$self->{args}}, "--$prefix$_[0]");
        };
  my $record_args  = sub { $_[0] = "--$_[0]"; push(@{$self->{args}}, @_);  };
  my ($no_tags, $all_tags) = (0, 0);
  my @branches;
  my @tags;
  my $result = main::GetOptions(
    "--help"           => sub { $self->help() },
    "--branch=s"       => sub { push(@branches, $_[1]) },
    "--tag=s"          => sub { push(@tags, $_[1]) },
    "--all-tags"       => \$all_tags,
    "--no-tags"        => \$no_tags,
    "commit!"          => sub { &$record_arg(@_) },
    "summary!"         => sub { &$record_arg(@_) },
    "no-stat|n"        => sub { &$record_arg(@_) },
    "squash!"          => sub { &$record_arg(@_) },
    "ff!"              => sub { &$record_arg(@_) },
    "strategy|s=s"     => sub { &$record_args(@_) },
    "rebase!"          => sub { &$record_arg(@_) },
    "quiet|q"          => sub { &$record_arg(@_) },
    "verbose|v"        => sub { &$record_arg(@_) },
    "append|a"         => sub { &$record_arg(@_) },
    "upload-pack=s"    => sub { &$record_args(@_) },
    "force|f"          => sub { &$record_arg(@_) },
    "tags"             => \$all_tags,
    "keep|k"           => sub { &$record_arg(@_) },
    "update-head-ok|u" => sub { &$record_arg(@_) },
    "--depth=i"        => sub { &$record_args(@_) },
    );
  die "Cannot specify both --all-tags and --no-tags!\n"
    if $all_tags && $no_tags;
  die "Cannot specify individual tags along with --all-tags or --no-tags!\n"
    if @tags && ($all_tags || $no_tags);
  my $repository = shift @ARGV;
  my @git_refspecs = @ARGV;

  # Record the tags or no-tags arguments
  push(@{$self->{args}}, "--tags") if $all_tags;
  push(@{$self->{args}}, "--no-tags") if $no_tags;

  #
  # Get the repository to pull from
  #
  my $repo_is_a_remote = 1;
  my $repo_specified = defined($repository);
  if ($repository) {
    push(@{$self->{args}}, $repository);
    $repo_is_a_remote = 0 if !RepoUtil::get_config("remote.$repository.url");
  } else {
    $repository = RepoUtil::get_default_push_pull_repository();
    if (!$repository) {
      # This line should never be reached
      die "Don't know what to pull!"
    }
    push(@{$self->{args}}, $repository) if (!$repo_specified && @branches);
  }

  #
  # Get the branch(es) to pull from
  #
  push(@branches, @git_refspecs);

  # If we were given explicit branches or tags to pull, then we know what
  # to pull.  Also, for compatibility with git, if the repository specified
  # is a url rather than a remotename, then we should pull from HEAD if
  # no other refspecs are specified.
  #
  # In all other cases...
  if ($repo_is_a_remote && !@branches && !@tags) {
    my $dont_know_what_to_pull = 0;

    # If we don't have a current branch, we can't tell what branch to merge
    my $branch = RepoUtil::current_branch();
    if (!$branch) {
      $dont_know_what_to_pull = 1;
      goto PULL_CHECK;
    }

    # If there's no default remote, we must ignore branch.$branch.merge so
    # we don't know what branch to merge
    my ($merge_branch, $default_remote);
    $default_remote = RepoUtil::get_config("branch.$branch.remote");
    if (!$default_remote) {
      $dont_know_what_to_pull = 1;
      goto PULL_CHECK;
    }

    # If the default remote doesn't match the specified repository, we must
    # ignore branch.$branch.remote so we don't know what branch to merge
    if ($repo_specified and $repository ne $default_remote) {
      $dont_know_what_to_pull = 1;
      goto PULL_CHECK;
    }

    # If branch.$branch.merge is not set we don't know what branch to merge
    $merge_branch = RepoUtil::get_config("branch.$branch.merge");
    if (!$merge_branch) {
      $dont_know_what_to_pull = 1;
      goto PULL_CHECK;
    }

    PULL_CHECK:
    # Even if we don't know what to pull, if the remote repository has exactly
    # one branch, then we can just pull from that.
    if ($dont_know_what_to_pull) {
      my $location = $repository || $default_remote;
      my $only_branch = RepoUtil::get_only_branch($location, "pull");
      push(@{$self->{args}}, $location) if !$repo_specified;
      push(@branches, $only_branch);
    }
  }

  foreach my $branch (@branches) {
    push(@{$self->{args}}, $branch);
  }
  foreach my $tag (@tags) {
    push(@{$self->{args}}, ("tag", $tag));
  }
}

sub run {
  my $self = shift;

  my @args = Util::quote_args(@{$self->{args}});
  return ExecUtil::execute("$GIT_CMD pull @args", ignore_ret => 1);
}

###########################################################################
# push                                                                    #
###########################################################################
package push;
@push::ISA = qw(subcommand);
INIT {
  $COMMAND{push} = {
    section => 'collaboration',
    about => 'Push local commits to a published repository'
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(
    git_repo_needed => 1,
    initial_commit_error_msg => "Error: No recorded commits to push.",
    @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg push [--bypass-modification-check] [--branch BRANCH] [--tag TAG]
          [--all-branches] [--all-tags] [--mirror] REPOSITORY

Description:
  Push committed changes in the current repository to a published remote
  repository.  Note that this command cannot be used to create a new remote
  repository; use 'eg publish' (which both creates a remote repository and
  pushes to it) if you need to do that.

  The push can fail if the remote repository has commits not
  in the current repository; this can be fixed by pulling and merging
  changes from the remote repository (use eg pull for this) and then
  repeating the push.  Note that for getting changes directly to a fellow
  developer's clone, you should have them use 'eg pull' rather than trying
  to use 'eg push' on your end.

  Branches and tags are typically considered private; thus only the current
  branch will be involved by default (no tags will be sent).  The
  --all-branches, --matching-branches, --all-tags, and --mirror options
  exist to extend the list of changes included.  The --branch and --tag
  options can be used to specifically send different changes.

  See 'eg help topic remote-urls' for valid syntax for remote repositories.

  If you frequently push to the same repository, you may want to set up a
  nickname for it (see 'eg help remote'), so that you can specify the
  nickname instead of the full repository URL every time.  Also, if you want
  to change the default repository and branch to push to, see 'eg track'.

Examples:
  Push commits in the current branch
      \$ eg push myserver.com:git-stuff/my-repo.git

  Push commits in all branches that already exist both locally and remotely
      \$ eg push --matching-branches ssh://web.site/path/to/project.git

  Push commits in all branches, including branches that do no already exist
  remotely, and all tags, to the remote nicknamed 'alice'
      \$ eg push --all-branches --all-tags alice

  Push all local branches and tags and delete anything on the remote end
  that is not in the current repository
      \$ eg push --mirror ssh://jim\@host.xz:22/~jim/project/published

  Create a two new tags locally, then push both
      \$ eg tag MY_PROJECT_1_0
      \$ eg tag USELESS_ALIAS_FOR_1_0
      \$ eg push --tag MY_PROJECT_1_0 --tag USELESS_ALIAS_FOR_1_0

  Push the changes in just the stable branch
      \$ eg push --branch stable 

Options
  --bypass-modification-check, -b
    To prevent you from pushing an incomplete set of changes, push
    typically checks whether you have new unknown files or modified files
    present and aborts if so.  You can bypass these checks with this
    option.

  --branch BRANCH
    Push commits in the specified branch.  May be reused multiple times to
    push commits in multiple branches.

    As an advanced option, one can use the syntax LOCAL:REMOTE for the
    branch.  For example, \"--branch my_bugfix:stable\" would mean to use
    the my_bugfix branch of the current repository to update the stable
    branch of the remote repository.

  --tag TAG
    Push the specified tag to the remote repository.

  --all-branches
    Push commits from all branches, including branches that do not yet exist
    in the remote repository

  --matching-branches
    Push commits from all branches that exist locally and remotely.  Note that
    this option is ignored if specific branches or tags are specified, or the
    --all-branches or --all-tags options.

  --all-tags
    Push all tags to the remote repository.

  --mirror
    Make the remote repository a mirror of the local one.  This turns on
    both --all-branches and --all-tags, but it also means that tags and
    branches that do not exist in the local repository will be deleted from
    the remote repository.
";
  $self->{'differences'} = "
  eg push is largely the same as git push, despite attempts to simplify in
  a number of areas:

    (1) push.default=tracking is the default if push.default is unset (git
        uses push.default=matching if push.default is unset).  This seems
        to match the intuition of most former cvs/svn users, though it is
        my one dangerous default change for existing git users.  Tough
        call, since the 'safe' defaults for each group are unsafe and/or
        confusing for the other.  A new --matching-branches flag is added
        to get the old behavior (the plain ':' refspec from git does the
        same, but --matching-branches is more self-documenting and also
        predates the ':' refspec).

    (2) eg prevents pushing into a bare repository as a push-side check
        rather than a receive-side check (when it can determine that the
        remote repository is bare -- i.e. if the repository url is for a
        locally mounted filesystem or uses ssh).  eg also allows the check
        to be overridden on the push-side (by specifying a refspec
        containing a ':' character).  This means it can work for users of
        existing repositories (created with git < 1.7), and it provides a
        solution that both avoids working copy inconsistency for new users
        while allowing more advanced users to do what they need on the same
        repository, and without forcing users to twiddle with the
        configuration of the remote repository.  However, this method
        doesn't work for repositories accessed via git://, and only works
        for ssh-accessed repositories if users have ssh setup to not need a
        password (kerberos, ssh-keys, etc.).

    (3) eg performs checks for uncommitted changes and newly created
        unknown files and warns/aborts if such exist when the user pushes
        (most former cvs/svn users are not yet familiar with the fact that
        only committed stuff gets pushed/pulled).  As with eg commit, such
        checks can be overridden with the -b flag.

    (4) eg provides extra --tag and --branch flags to make command lines
        more self-documenting and to avoid excessively early introduction
        of refspecs (a very confusing topic for new users).  However,
        refspecs still work with eg push, and users can learn about them by
        running 'eg help topic refspecs'.
";
  return $self;
}

sub _get_push_repository ($) {
  my ($repository) = @_;

  if (defined $repository) {
    return RepoUtil::get_config("remote.$repository.pushurl") ||
           RepoUtil::get_config("remote.$repository.url") ||
           $repository;
  } else {
    return RepoUtil::get_config("remote.origin.url")
  }
}

# _check_if_bare: Return whether the given repository is bare.  Returns
# undef the repository doesn't specify a valid repository or the repository
# is not of a type where we can determine bare-ness.  Otherwise returns
# either the string "true" or "false".
sub _check_if_bare ($) {
  my $repository = shift;

  # Don't know how to check rsync, http, https, or git repositories to see
  # if they are bare.
  return undef if $repository =~ m#^(rsync|http|https|git)://#;

  #
  # Check local directories
  #
  if ($repository =~ m#^file://(.*)#) {
    $repository = $1;
  }
  if (-d $repository) {
    my $orig_dir = main::getcwd();
    chdir($repository);

    my ($ret, $output) = 
      ExecUtil::execute_captured("$GIT_CMD rev-parse --is-bare-repository",
                                 ignore_ret => 1);

    chdir($orig_dir);
    return undef if $ret != 0;
    chomp($output);
    return $output;
  }

  #
  # Check ssh systems
  #
  my ($user, $machine, $port, $path) = Util::split_ssh_repository($repository);
  return undef if !defined $machine || !defined $path;

  my ($ret, $output) = 
    ExecUtil::execute_captured(
      "ssh $port -q -o BatchMode=yes $user$machine 'cd $path && $GIT_CMD rev-parse --is-bare-repository'",
      ignore_ret => 1);
  return undef if $ret != 0;
  chomp($output);
  my @lines = split('\n', $output);
  my $result = $lines[-1];
  # If ssh or git itself failed, $ret could still be 0 but $result could be
  # something other than "true" or "false"
  return undef if (! grep {$_ eq $result} ["true", "false"]);
  return $result;
}

sub preprocess {
  my $self = shift;
  my $package_name = ref($self);

  #
  # Parse options
  #
  $self->{args} = [];
  my $record_arg   = sub { push(@{$self->{args}}, "--$_[0]"); };
  my $record_args  = sub { $_[0] = "--$_[0]"; push(@{$self->{args}}, @_);  };
  my ($all_branches, $matching_branches, $all_tags, $mirror) = (0, 0, 0, 0);
  my ($thin, $repo) = (0, 0);
  my @branches;
  my @tags;
  my $bypass_modification_check = 0;
  my $result = main::GetOptions(
    "--help"              => sub { $self->help() },
    "--branch=s"          => sub { push(@branches, $_[1]) },
    "--tag=s"             => sub { push(@tags, $_[1]) },
    "--all-branches|all"  => \$all_branches,
    "--matching-branches" => \$matching_branches,
    "--all-tags"          => \$all_tags,
    "--mirror"            => \$mirror,
    "--dry-run"           => sub { &$record_arg(@_) },
    "--receive-pack=s"    => sub { &$record_args(@_) },
    "force|f"             => sub { &$record_arg(@_) },
    "repo=s"              => \$repo,
    "thin"                => sub { &$record_arg(@_) },
    "no-thin"             => sub { &$record_arg(@_) },
    "verbose|v"           => sub { &$record_arg(@_) },
    "set-upstream|u"      => sub { &$record_arg(@_) },
    "bypass-modification-check|b" => \$bypass_modification_check,
    );
  die "Cannot specify individual branches and request all branches too!\n"
    if @branches && ($all_branches || $mirror);
  die "Cannot specify individual tags and request all tags too!\n"
    if @tags && ($all_tags || $mirror);
  my $repository = shift @ARGV;
  my @git_refspecs = @ARGV;

  if (!$bypass_modification_check) {
    my $status = RepoUtil::commit_push_checks($package_name,
                                              {unknown => 1,
                                               changes => 1,
                                               unmerged_changes => 1});
  } else {
    # Record the set of unknown files we ignored with -b, so the -b flag
    # isn't needed next time.
    RepoUtil::record_ignored_unknowns();
  }

  push(@{$self->{args}}, "--all")    if $all_branches;
  push(@{$self->{args}}, "--tags")   if $all_tags;
  push(@{$self->{args}}, "--mirror") if $mirror;

  my $default_specified = 0;
  $default_specified = 1  if $all_branches;
  $default_specified = 1  if $all_tags;
  $default_specified = 1  if $mirror;

  #
  # Get the repository to push to
  #
  if (defined $repository && $repository =~ m#^-#) {
    die "Invalid repository to push to: $repository\n";
  }
  my $remote;
  if ($repository) {
    push(@{$self->{args}}, $repository);
  } elsif (!$repository && (@branches || @tags || !$default_specified)) {
    $repository = RepoUtil::get_default_push_pull_repository();
    push(@{$self->{args}}, $repository);
    $remote = $repository;
  } else {
    # Just drop through to the git push defaults.
  }

  #
  # Prevent pushing to a non-bare repository (on local filesystem or over
  # ssh; I don't know how to detect other cases)...unless user explicitly
  # specifies both source and destination references explicitly
  #
  my $remote_chk = $remote || $repository;
  $repository = _get_push_repository($repository);
  my $push_to_non_bare_repo;
  if ($repository) {

    # If the user uses a refspec including a colon character, assume
    # they know what they are doing and skip the non-bare check
    if (! grep {$_ =~ /:/} @git_refspecs) {

      # Check if we have already determined this repository to be bare
      my $is_bare;
      $is_bare = RepoUtil::get_config("remote.$remote.bare") if $remote;
      if (defined $is_bare) {
        $push_to_non_bare_repo = ($is_bare eq "false");
      } else {
        $is_bare = _check_if_bare($repository);
        if (defined $is_bare && defined $remote) {
          RepoUtil::set_config("remote.$remote.bare", $is_bare);
        }
        $push_to_non_bare_repo = (defined $is_bare && $is_bare eq "false");
      }
    }
  }
  # Throw an error if the user is trying to push to a bare repository
  # (and not using a refspec with a colon character)
  if ($push_to_non_bare_repo) {
    print STDERR <<EOF;
Aborting: You are trying to push to a repository with an associated working
copy, which will leave its working copy out of sync with its repository.
Rather than pushing changes to that repository, you should go to where that
repository is located and pull changes into it (using eg pull).  If you
know what you are doing and know how to deal with the consequences, you can
override this check by explicitly specifying source and destination
references, e.g.
  eg push REMOTE BRANCH:REMOTE_BRANCH
Please refer to
  eg help topic refspecs
to learn what this syntax means and what the consequences of overriding this
check are.
EOF
    exit 1;
  }

  #
  # Get the default branch to push to, if needed
  #
  push(@{$self->{args}}, ":") if $matching_branches;
  $default_specified = 1  if $matching_branches;

  if (!@branches && !@tags && !@git_refspecs && !$default_specified) {
    # User hasn't specified what to push; default choices:
    # 1 - remote.$remote.(push|mirror) options
    my $default_known = 0;
    if (defined(RepoUtil::get_config("remote.$remote_chk.push")) ||
        defined(RepoUtil::get_config("remote.$remote_chk.mirror"))) {
      $default_known = 1;
    }
    # 2 - push.default option
    if (defined(RepoUtil::get_config("push.default"))) {
      $default_known = 1;
    }
    # 3 - branch.$branch.merge option
    if (!$default_known) {
      my $branch = RepoUtil::current_branch();
      my $push_branch = RepoUtil::get_config("branch.$branch.merge");
      if (defined $push_branch) {
        $push_branch =~ s#refs/heads/##;
        push(@{$self->{args}}, "$branch:$push_branch");
        $default_known = 1;
      }
    }
    # 4 - the only branch that exists at the remote end
    if (!$default_known && defined $repository) {
      my $only_branch = RepoUtil::get_only_branch($repository, "push");
      push(@{$self->{args}}, $only_branch);
    }
  }

  #
  # Get the branch(es) to push
  #
  push(@branches, @git_refspecs);
  push(@{$self->{args}}, @branches);
  foreach my $tag (@tags) {
    push(@{$self->{args}}, ("tag", $tag));
  }
}

sub run {
  my $self = shift;

  my @args = Util::quote_args(@{$self->{args}});
  return ExecUtil::execute("$GIT_CMD push @args", ignore_ret => 1);
}

###########################################################################
# rebase                                                                  #
###########################################################################
package rebase;
@rebase::ISA = qw(subcommand);
INIT {
  $COMMAND{rebase} = {
    extra => 1,
    section => 'timesavers',
    about => "Port local commits, making them be based on a different\n" .
             "                repository version"
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(
    git_repo_needed => 1,
    initial_commit_error_msg => "Error: No recorded commits to rewrite.",
    @_);
  bless($self, $class);
  #
  # Note: Parts of help were taken from the git-rebase manpage, which
  # was also available under GPLv2.
  #
  $self->{'help'} = "
Usage:
  eg rebase [-i | --interactive] [ --since SINCE ] [ --onto ONTO ]
            [ --against AGAINST ] [BRANCH_TO_REBASE]
  eg rebase [ --continue | --skip | --abort ]

Description:
  Rewrites commits on a branch, making them be based on a different
  repository version.  Technically, the old commits are not overwritten or
  deleted (only new ones are written), meaning that other branches sharing
  the same commits will be unaffected and users can undo a rebase (until
  the unused commits are cleaned up after a few weeks).

  WARNING:
    Rebasing commits in a branch is an advanced operation which changes
    history in a way that will cause problems for anyone who already has a
    copy of the branch in their repository when they try to pull updates
    from you.  This may cause them to experience many conflicts in their
    merges and require them to resolve those conflicts manually, or rewrite
    their own history, or even toss out their changes and simply accept
    your version.  (The last of those options is common enough that there
    is a special method of pulling and pushing changes in such cases; see
    'eg help topic refspecs' for more details.)

  Non-interactive rebase (running without the --interactive or -i flags):
    Specifying which commits to rewrite and what to rewrite them relative
    to involves specifying up to three branches or revisions: SINCE, ONTO,
    and BRANCH_TO_REBASE.  eg will take all commits in the BRANCH_TO_REBASE
    branch that are not in the SINCE branch, and record them as commits on
    top of the tip of the ONTO branch.  The ONTO and SINCE branches are not
    changed by this operation.  The BRANCH_TO_REBASE branch is changed to
    record the tip of the newly written branch.

    See also the \"If a conflict occurs\" section below.

  Interactive rebase (running with the --interactive or -i flag):
    Interactive rebasing allows you a chance to edit the commits which are
    rebased, including
      * reordering commits
      * removing commits
      * combining multiple commits into one commit
      * amending commits to include different changes or log messages
      * splitting one commit into multiple commits
    When running interactively, eg rebase will begin by making a list of
    the commits which are about to be rebased and allow you to change the
    the list before rebasing.  The list will include one commit per line,
    allowing you to
      * reorder commits by reordering lines
      * removing commits by removing lines
      * combining multiple commits into one, by changing 'pick' to 'squash'
        at the beginning of each line of the commits you want combined
        *except* the first
      * amend a commit by changing the 'pick' at the beginning of the line
        of the relevant commit to 'edit'.  This will make eg rebase stop
        after applying that commit, allowing you to make changes and run
        'eg commit --amend' followed by 'eg rebase --continue'.
      * split one commit into multiple commits by changing 'pick' at the
        beginning of the line of the relevant commit to 'edit'.  This will
        make eg rebase stop *after* applying that commit, allowing you to
        manually undo that commit while keeping the changes in the working
        copy (with 'eg reset HEAD~1') and then make multiple commits (with
        'eg commit') before running 'eg rebase --continue'.  Note that eg
        stash may come in handy for testing the split commits.

  If a conflict occurs:
    Rebase will stop at the first problematic commit and leave conflict
    markers (<<<<<<) in the tree.  You can use eg status and eg diff to
    find the problematic files and locations.  Once you edit the files to
    fix the conflicts, you can run
      eg resolved FILE
    to mark the conflicts in FILE as resolved.  Once you have resolved all
    conflicts, you can run
      eg rebase --continue
    If you simply want to skip the problematic patch (and end up with one
    less commit), you can instead run
      eg rebase --skip
    Alternatively, to abort the rebase and return to your previous state,
    you can run
      eg rebase --abort

Examples:
  Take a branch named topic that was split off of the master branch, and
  update it to be based on the new tip of master.
      \$ eg rebase --since master --onto master topic
    Pictorally, this changes:
                 A---B---C topic
                /
           D---E---F---G master
    into
                         A'--B'--C' topic
                        /
           D---E---F---G master

  Same as the the above example, with less typing
      \$ eg rebase --against master topic

  Same as the last two examples, assuming topic is the current branch
      \$ eg rebase --against master

  Take a branch named topic that is based off of a branch named next, which
  is in turn based off master, and rewrite topic so that it appears to be
  based off the most recent version of master.
      \$ eg rebase --since next --onto master topic
    Pictorally, this changes
           o---o---o---o---o  master
                \\
                 o---o---o---o---o  next
                                  \\
                                   o---o---o  topic
    into
           o---o---o---o---o  master
               |            \\
               |             o'--o'--o'  topic
                \\
                 o---o---o---o---o  next

  Take just the last two commits of the current branch, and rewrite them
  to be relative to the commit just before the most recent on the master
  branch.
      \$ eg rebase --since current~2 --onto master~1 current
    Pictorally, this changes:
                    A---B---C---D---E  current
                   /
           F---G---H---I---J---K master
    into
                            D'---E' current
                           /
           F---G---H---I---J---K master

  Reorder the last two commits on the current branch
      \$ eg rebase --interactive --since HEAD~2
  (Then edit the file you are presented with and change the order of the
  two lines beginning with 'pick')
    Pictorally, this changes:
           A---B---C---D---E---F master
    into
           A---B---C---D---F'---E' master

Options:
  --since SINCE
    Upstream branch to compare against; only commits not found in this
    branch will be rebased.  Note that if --onto is not specified, the
    value of SINCE will be used for that as well.

    The value of SINCE is not restricted to existing branch names; any
    valid revision can be used (due to the fact that all revisions know
    their parents and a revision plus its ancestors can define a branch).

  --onto ONTO
    Starting point at which to create the new commits.  If the --onto
    option is not specified, the starting point is whatever is provided by
    the --since option.  Any valid revision can be used for the value of
    ONTO.

  --against AGAINST
    An alias for --since AGAINST, provided to make command lines clearer
    when the --onto flag is not also used.  (Typically, --against is used
    if --onto is not, and --since is used if --onto is, but --against and
    --since can be used interchangably.)

  --interactive, -i
    Make a list of the revisions which are about to be rebased and let the
    user edit that list before rebasing.  Can be used to split, combine,
    remove, insert, reorder, or edit commits.

  --continue
    Restart the rebasing process after resovling a conflict

  --skip
    Restart the rebasing process by skipping the current patch (resulting
    in a rewritten history with one less commit).

  --abort
    Abort the stopped rebase operation and restore the original branch
";
  $self->{'differences'} = "
  The only differences between eg rebase and git rebase are cosmetic;
  further, eg rebase accepts all options and flags that git rebase accepts.

  eg adds the identically behaved flags --since and --against in
  preference to using the position of the branch/revision name on the
  command line.  Note that
    git rebase master
  is somewhat confusing in that it isn't rebasing master but the current
  branch.  To make this clearer, eg allows (and encourages) the form
    eg rebase --against master
  The reason that both --against and --since flags were added (with
  identical behavior), is that the former makes for clearer command lines
  when the --onto flag is not also used.
";
  return $self;
}

sub preprocess {
  my $self = shift;

  #
  # Parse options
  #
  $self->{args} = [];
  my $record_arg   = sub { push(@{$self->{args}}, "--$_[0]"); };
  my $record_args  = sub { $_[0] = "--$_[0]"; push(@{$self->{args}}, @_);  };
  my $since;
  my $result = main::GetOptions(
    "--help"              => sub { $self->help() },
    "interactive|i"       => sub { &$record_arg(@_) },
    "verbose|v"           => sub { &$record_arg(@_) },
    "merge|m"             => sub { &$record_arg(@_) },
    "C=i"                 => sub { &$record_args(@_) },
    "whitespace=s"        => sub { push(@{$self->{args}},"--whitespace=$_[1]") },
    "preserve-merges|p"   => sub { &$record_arg(@_) },
    "onto=s"              => sub { &$record_args(@_) },
    "against=s"           => sub { $since=$_[1] },
    "since=s"             => sub { $since=$_[1] },
    "continue"            => sub { &$record_arg(@_) },
    "skip"                => sub { &$record_arg(@_) },
    "abort"               => sub { &$record_arg(@_) },
    );
  die "Too many branches/revisions specified\n"
    if @ARGV > 1 && defined $since;
  push(@{$self->{args}}, $since) if defined $since;
  push(@{$self->{args}}, @ARGV);
}

sub run {
  my $self = shift;

  my @args = Util::quote_args(@{$self->{args}});
  return ExecUtil::execute("$GIT_CMD rebase @args", ignore_ret => 1);
}

###########################################################################
# remote                                                                  #
###########################################################################
package remote;
@remote::ISA = qw(subcommand);
INIT {
  $COMMAND{remote} = {
    unmodified_behavior => 1,
    extra => 1,
    section => 'collaboration',
    about => 'Manage named remote repositories',
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(git_repo_needed => 1, @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg remote
  eg remote add REMOTENAME URL
  eg remote rm REMOTENAME
  eg remote update GROUPNAME

Description:
  eg remote is a convenience utility to make it easy to track changes from
  multiple remote repositories.  It is used to
    1) Set up
         REMOTENAME -> URL
       aliases that can be used in the place of full urls to simplify
       commands such as push or pull
    2) Pulling updates from multiple branches of a remote repository at
       once and storing them in remote tracking branches (which differ from
       normal branches only in that they have a prefix of REMOTENAME/ in
       their name).
    3) Pulling updates from multiple branches of multiple remote
       repositories at once, storing them all in remote tracking branches.

Examples:
  The examples section is split into three categories:
    1) Managing which remotes exist:
    2) Using one or more existing remotes
    3) Using remote tracking branches created through usage of remotes

  Category 1: Managing which remotes exist:

    List which removes exist
      \$ eg remote
    or, list remotes and their urls (among other things)
      \$ eg info

    Add a new remote for the url ssh://some.machine.org//path/to/repo.git,
    giving it the name jim
      \$ eg remote add jim ssh://some.machine.org//path/to/repo.git

    Add a new remote for the url git://composit.org//location/eyecandy.git,
    giving it the name bling
      \$ eg remote add bling git://composit.org//location/eyecandy.git

    Delete the remote named bob, and remove all related remote tracking
    branches (i.e. those branches whose names begin with \"bob/\"), as well
    as any associated configuration settings
      \$ eg remote rm bob
    
  Category 2: Using one or more existing remotes

    Pull updates for all branches of the remote jill, storing each in a
    remote tracking branch of the local repository named jill/BRANCH.
      \$ eg fetch jill

    Pull changes from the magic branch of the remote merlin and merge it
    into the current branch (i.e. standard pull behavior) AND also update
    all remote tracking branches associated with the remote (i.e. act as if
    'eg fetch merlin' was also run)
      \$ eg pull --branch magic merlin

    Grab updates from all remotes, i.e. run 'eg fetch REMOTE' for each
    remote.
      \$ eg remote update
    (Technically, some remotes could be manually configured to be excluded
    from this update.)

    Grab updates from all remotes in the group named friends (created by
    use of 'eg config remotes.friends \"REMOTE1 REMOTE2...\"'), i.e. run
    'eg fetch REMOTE' for each remote in the friends group
      \$ eg remote update friends

  Category 3: Using remote tracking branches created through usage of remotes

    List all remote tracking branches
      \$ eg branch -r

    Merge the remote tracking branch jill/stable into the current branch
      \$ eg merge jill/stable

    Get a history of the changes on the bling/explode branch
      \$ eg log bling/explode

    Create a new branch named my-testing based off of the remote tracking
    branch jenny/testing
      \$ eg branch my-testing jenny/testing
";
  return $self;
}

###########################################################################
# reset                                                                   #
###########################################################################
package reset;
@reset::ISA = qw(subcommand);
INIT {
  $COMMAND{reset} = {
    extra => 1,
    section => 'modification',
    about => 'Forget local commits and (optionally) undo their changes'
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(git_repo_needed => 1, @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg reset [--working-copy | --no-unstaging] [REVISION]

Description:
  Forgets local commits for the active branch and (optionally) undoes their
  changes in the working copy.  If you have staged changes (changes you
  explictly marked as ready for commit) this function also unstages them by
  default.  See 'eg help topic staging' to learn about the staging area.

  From a computer science point of view, eg reset moves the current branch
  tip to point at an older commit, and also optionally changes the working
  copy and staging area to match the version of the repository recorded in
  the older commit.

  Note that this function should be used with caution; it is often used to
  discard unwanted data or to modify recent local \"history\" of commits.
  You want to be careful to not also discard wanted data, and modifying
  history is a bad idea if someone has already obtained a copy of that
  local history from you (rewriting history makes merging and updating
  problematic).

Examples:
  Throw away all changes since the last commit
      \$ eg reset --working-copy HEAD
  Note that HEAD always refers to the current branch, and the current
  branch always refers to its last commit.

  Throw away the last three commits and all current changes (this is a bad
  idea if someone has gotten a copy of these commits from you; this should
  only be done for truly local changes that you no longer want).
      \$ eg reset --working-copy HEAD~3

  Unrecord the last two commits, but keep the changes corresponding to these
  commits in the working copy.  (This can be used to fix a set of \"broken\"
  commits.)
      \$ eg reset HEAD~2

  While working on the \"stable\" branch, you decide that the last 5 commits
  should have been part of a separate branch.  Here's how you retroactively
  make it so:
      Verify that your working copy is clean...then
      \$ eg branch difficult_bugfix
      \$ eg reset --working-copy HEAD~5
      \$ eg switch difficult_bugfix
  The first step creates a new branch that initially could be considered an
  alias for the stable branch, but does not switch to it.  The second step
  moves the stable branch tip back 5 commits and modifies the working copy
  to match.  The last step switches to the difficult_bugfix branch, which
  updates the working copy with the contents of that branch.  Thus, in the
  end, the working copy will have the same contents as before you executed
  these three steps (unless you had local changes when you started, in
  which case those local changes will be gone).

  Stage files (mark changes in them as good and ready for commit but
  without yet committing them), then change your mind and unstage all
  files.
      \$ eg stage foo.c bla.h
      \$ eg reset HEAD
  Note that using HEAD as the commit means to forget all commits since HEAD
  (always an empty set) and undo any staged changes since that commit.

Options:
  --working-copy
    Also make the working tree match the version of the repository recorded
    in the specified commit.  If this option is not present, the working
    copy will not be modified.

  --no-unstaging
    Do not modify the staging area; only change the current branch tip to
    point to the older commit.

  REVISION
    A reference to a recorded version of the repository, defaulting to HEAD
    (meaning the most recent commit on the current branch).  See 'eg help
    topic revisions' for more details.

";
  $self->{'differences'} = '
  The only differences between eg reset and git reset are cosmetic;
  further, eg reset accepts all options and flags that git reset accepts.

  git reset uses option names of --soft, --mixed, and --hard.  While eg
  reset will accept these option names for compatibility, it provides
  alternative names that are more meaningful:
    --working-copy     <=> --hard
    --no-unstaging     <=> --soft
  There is no alternate name for --mixed, since it is the default and thus
  does not need to appear on the command line at all.

  The modified revert command of eg is encouraged for reverting specific
  files, though eg reset has the same file-specific reverting that git
  reset does.
';
  return $self;
}

sub preprocess {
  my $self = shift;

  #
  # Parse options
  #
  my ($hard, $soft) = (0, 0);
  return if (scalar(@ARGV) > 0 && $ARGV[0] eq "--");

  my $result = main::GetOptions(
    "--help"         => sub { $self->help() },
    "--working-copy" => \$hard,
    "--no-unstaging" => \$soft,
    );
  die "Cannot specify both --working-copy and --no-unstaging!\n"
    if $hard && $soft;
  unshift(@ARGV, "--hard") if $hard;
  unshift(@ARGV, "--soft") if $soft;
}

###########################################################################
# resolved                                                                #
###########################################################################
package resolved;
@resolved::ISA = qw(subcommand);
INIT {
  $COMMAND{resolved} = {
    new_command => 1,
    extra => 1,
    section => 'compatibility',
    about => 'Declare conflicts resolved and mark file as ready for commit'
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(git_repo_needed => 1,
                                git_equivalent => 'add',
                                @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg resolved PATH...

Description:
  Declare conflicts resolved for the specified paths, and mark contents of
  those files as ready for commit.

Examples
  After fixing any update or merge conflicts in foo.c, declare the fixing to
  be done and the contents ready to commit.
      \$ eg resolved foo.c
";
  $self->{'differences'} = "
  eg resolved is a command new to eg that is not part of git.  It is
  almost synonymous with git add; however, there are two differences:
  (a) eg resolved will work on a locally deleted file in the unmerged
  state (git add will complain that there's 'No such file or
  directory', and some users have had difficulty trying to find out
  that they needed to run git rm on such files), (b) eg resolved only
  works on files in the unmerged state (reporting an error if files
  not in such a state are specified).
";
  return $self;
}

sub run {
  my $self = shift;

  die "Error: Must specify paths to resolve.\n" if !@ARGV;
  @ARGV = Util::quote_args(@ARGV);

  # Determine which files are actually unmerged
  my ($ret, $output) =
    ExecUtil::execute_captured("$GIT_CMD ls-files -u --error-unmatch @ARGV",
      ignore_ret => 1);
  chomp($output);
  my @lines = split('\n', $output);

  # If there are some files that do not have conflicts, scream at the user
  if ($ret != 0) {
    my @not_unmerged_paths;

    foreach my $line (@lines) {
      if ($line =~ m/^error: pathspec '(.*?)' did not match any file/) {
        push(@not_unmerged_paths, $1);
      }
    }
    if (@not_unmerged_paths) {
      die "Error: The following are not unmerged files and thus don't " .
          "need resolving:\n  " . join("\n  ", @not_unmerged_paths) . "\n";
    } else {
      die "$output\n";
    }
  }

  # Determine the unmerged files (users may have passed a directory which
  # has both unmerged files and modified but unstaged ones; we only want
  # to stage the unmerged files from such a directory).
  my %files;
  foreach my $line (@lines) {
    $line =~ m/^\d+ [0-9a-f]+ \d\t(.*)$/;
    $files{$1} = 1;
  }
  my @unmerged_files = keys %files;

  # Run add -u instead of just add, since we want locally deleted files to
  # be picked up as well.
  return ExecUtil::execute("$GIT_CMD add -u @unmerged_files", ignore_ret => 1);
}

###########################################################################
# revert                                                                  #
###########################################################################
package revert;
@revert::ISA = qw(subcommand);
INIT {
  $COMMAND{revert} = {
    section => 'modification',
    about => 'Revert local changes and/or changes from previous commits'
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(git_repo_needed => 1, git_equivalent => '', @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg revert [[-m PARENT_NUMBER] --in REVISION | --since REVISION]
            [--staged | --unstaged] [--] [PATH...]

Description:
  eg revert undoes edits to your files, without changing the commit history
  or changing which commit is active.  (If you are looking for a different
  kind of 'undo'; they are discussed and contrasted below.)  There are many
  options for what to revert; you may want to jump ahead to the examples
  section below and then come back and read the full description.

  The work eg revert does includes discarding local modifications, removing
  recorded conflict states, undoing add or stage operations (i.e. unstaging
  files), and restoring deleted files to the previously recorded version.
  If you revert changes since some revision prior to the most recent,
  revert will also remove any files which were added in a later revision.

  By default, eg revert will revert edits since the last commit(*).  One
  can specify a different revision to revert file contents back to, or
  revert edits made in a single previous commit(**).  (Advanced usage note:
  eg revert will undo both staged and unstaged changes by default; you can
  request only one of these; see 'eg help topic staging' for more details
  on what staged and unstaged changes are.)

  (*) For an initial or root commit, eg revert will simply undo adds.  When
  in an uncompleted merge state, it is an error to not specify which commit
  to revert relative to (with the --since flag).

. (**) When reverting the changes made *in* a merge commit, the revert
  command needs to know which parent of the merge the revert should be
  relative to.  This can be specified using the -m option.

  To avoid accidental loss of local changes, nothing will be done when no
  arguments are provided to eg revert.  However, eg revert will check for
  various special cases (from the different types of 'undo' below), and try
  to provide an error message tailored to any special circumstances
  relevant to you.

  === Comparison of different types of 'undo' available ===
  * Back up or switch to an earlier commit (eg switch)
  * Make a new commit to reverse the changes of a previous commit (eg
    cherry-pick -R)
  * Remove commits from history (eg reset OR eg rebase --interactive)
  * Reverting edits, without switching commits or changing commit history
    (eg revert)
  * Abort an incomplete operation
    * Incomplete merge:      eg revert --since HEAD
    * Unfinished rebase:     eg rebase --abort
    * Unfinished apply mail: eg am --abort
    * Unfinished bisect:     eg bisect reset

Examples:
  Undo changes since the last commit on the current branch to bar.h and
  foo.c.  This can be done with either of the following methods:
      \$ eg revert bar.h foo.c                      # Method #1
      \$ eg revert --since HEAD bar.h foo.c         # Method #2, more explicit

  While on the bling branch, revert the changes in the last 3 commits (as
  well as any local changes) to any file under the directory docs.  This
  can be done by:
      \$ eg revert --since bling~3 docs

  While on the stable branch, you determine that the seventh commit prior
  to the most recent had a faulty change to foosubdir and baz.txt and you
  simply want to undo it.  This can be accomplished by:
      \$ eg revert --in stable~7 -- foosubdir baz.txt

  You decide that all changes to foobar.cpp in your working copy and in the
  last 2 commits are bad and want to revert them.  This is done by:
  of:
      \$ eg revert --since HEAD~2 -- foobar.c

  You decide that some of the changes in the merge commit HEAD~4 are bad.
  You would like to revert the changes to baz.py in HEAD~4 relative to its
  second parent.  This can be accomplished as follows:
      \$ eg revert -m 2 --in HEAD~4 baz.py
  
  (Advanced) Undo a previous stage, marking changes in foo.c as not
  being ready for commit (this is equivalent to eg unstage foo.c):
      \$ eg revert --staged foo.c

  (Advanced) Undo changes since the most recent stage to soopergloo.f77
      \$ eg revert --unstaged soopergloo.f77

  (Advanced) You decide that the changes to abracadabra.xml made in commit
  HEAD~8 are bad.  You want to revert those changes in the version of
  abracadabra.xml but only to your working copy.  This is done by:
      \$ eg revert --unstaged --in HEAD~8 -- abracadabra.xml

Options:
  --since
    Revert the changes made since the specified commit, including any local
    changes.  This takes the difference between the specified commit and
    the current version of the files and reverses these changes.

  --in
    Revert the changes made in the specified commit.  This takes the
    difference between the parent of the specified commit and the specified
    commit and reverse applies it.

  REVISION
    A reference to a recorded version of the repository, defaulting to HEAD
    (meaning the most recent commit on the current branch).  See 'eg help
    topic revisions' for more details.

  -m PARENT_NUMBER
    When reverting the changes made in a merge commit, the revert command
    needs to know which parent of the merge the revert should be relative
    to.  Use this flag with the parent number (1, 2, 3...) to specify which
    parent commit to revert relative to.

    Can only be used with the --in option.

  --staged
    Make changes only to the staged (explicitly marked as ready to be
    committed) version of files.

  --unstaged
    Make changes only to the unstaged version of files, i.e. only to the
    working copy.

  --
    This option can be used to separate command-line options and commits
    from the list of files, (useful when filenames might be mistaken for
    command-line options or be mistaken as a branch or tag name).

  PATH...
    One or more files or directories.  The changes reverted will be limited
    to the listed files or files below the listed directories.
";
  $self->{'differences'} = '
  eg revert is similar to the revert command of svn, hg, bzr, or darcs.  It
  is not provided by any one git command; it overlaps with about five
  different git commands in specific cases.  git users wanting the
  functionality in eg revert will typically be guided by expert git users
  towards whichever git command seems like the most natural fit for the
  particular case the user asks about.  Quite often, such users will
  continue using the command they are given for subsequent situations...and
  will often stumble across multiple cases where the git command no longer
  matches the wanted revert behavior.

  git does provide a command called revert, which is a subset of the
  behavior of eg cherry-pick:
    git revert COMMIT
  is the same as
    eg cherry-pick -R COMMIT
  which is, modulo the automatic commit message provided by git revert, the
  same as
    eg revert --in COMMIT && eg commit
  Note that while eg revert --in may look similar to git revert, the former
  is about undoing changes in just the working copy, is typically
  restricted to a specific subset of files, and is usually just one change
  of many towards testing or creating something new to be committed.  The
  latter is always concerned with reverse applying an entire commit, and is
  almost always used to immediately record that change.

  Note that git revert commands are invalid syntax in eg (since eg revert
  always requires the --since or --in flags to be specified whenever a
  commit is).  This means that eg can catch such cases and notify git
  users to adopt the eg cherry-pick -R command.

  Due to these changes, eg revert should be much more welcoming to users of
  svn, hg, bzr, or darcs.  It also provides a simple discovery mechanism
  for existing git users to allow them to easily work with eg.
  Additionally, these changes also make the reset and checkout/switch
  subcommands of eg easier to understand by limiting their scope instead of
  each having two very different capabilities.  (Technically, eg reset and
  eg checkout still have those capabilities for backwards compatibility, I
  just omit them in the documentation.)

  It seems that perhaps eg revert could be extended further, to accept
  things like
      \$ eg revert --in HEAD~8..HEAD~5 foo.c
  to allow reverting changes made in a range of commits.  The --in could
  even be optional in such a case, since the range makes it clear what is
  wanted.
';
  return $self;
}

sub preprocess {
  my $self = shift;

  my ($cur_dir, $top_dir, $git_dir) = RepoUtil::get_dirs();
  my $initial_commit = RepoUtil::initial_commit();

  # Parsing opts
  my ($staged, $unstaged, $in) = (0, 0, -1);
  my $m;
  my $rev;
  my $result = main::GetOptions(
    "--help"         => sub { $self->help() },
    "-m=i"           => \$m,
    "--staged"       => \$staged,
    "--unstaged"     => \$unstaged,
    "--in=s"         => sub { $in = 1; $rev = $_[1]; },
    "--since=s"      => sub { $in = 0; $rev = $_[1]; },
    );

  # Parsing revs and files
  my ($opts, $revs, $files) = RepoUtil::parse_args([], @ARGV);
  unshift(@$revs, $rev) if defined($rev);

  #
  # Big ol' safety checks and warnings
  #
  if (!@$revs && !@$files) {
    my $files_modified = RepoUtil::files_modified();
    if (-f "$self->{git_dir}/MERGE_HEAD") {
      print STDERR<<EOF;
Aborting: no revisions or files specified to revert.  If you want to abort
your incomplete merge, try 'eg reset --working-copy HEAD'.
EOF
      exit 1;
    }
    elsif (-d "$self->{git_dir}/rebase-merge" ||
           -d "$self->{git_dir}/rebase-apply") {
      print STDERR<<EOF;
Aborting: no revisions or files specified to revert.  If you want to abort
your incomplete rebase, try:
  eg rebase --abort
EOF
      exit 1;
    }
    elsif (!$files_modified && !$initial_commit) {
      my $active_branch = RepoUtil::current_branch() || 'HEAD';
      print STDERR<<EOF;
There are no local changes to revert and you specified no revisions to revert
(or revert back to).  Please specify a revision with --in or --since.
Alternatively, if you want to modify commits instead of just the working copy
then use reset instead of revert:

If you want to undo a rebase or a merge (including a pull or update), try:
  eg reset --working-copy ORIG_HEAD
If you want to undo the last commit (but keep its changes in the working copy),
try:
  eg reset $active_branch~1
If you just want to amend the last commit without undoing it, make the
additional changes you want and run:
  eg commit --amend
If you want to undo previous reset commands, get the appropriate reflog
reference from eg reflog (for example, using HEAD\@{1} for <REF>) and run:
  eg reset --working-copy <REF>
EOF
      exit 1;
    }
    elsif (!$initial_commit) {
      print STDERR<<EOF;
Aborting: no revisions or files specified.  If you want to revert and lose
all changes since the last commit, try adding the arguments
  --since HEAD
to the end of your command.
EOF
      exit 1;
    } else {
      print STDERR<<EOF;
Aborting: no files specified.
EOF
      exit 1;
    }
  }

  # Sanity checks
  die "Cannot specify -m without specifying --in.\n" if !$in && defined($m);
  die "Can only specify one revision\n" if @$revs > 1;
  die "No revision specified after --in\n"    if ($in == 1 && !@$revs);
  die "No revision specified after --since\n" if ($in == 0 && !@$revs);
  if ($in == -1 && @$revs) {
    die "You must specify either --in or --since when specifying a revision.\n".
        "(git users:) If you are used to git revert; try running\n".
        "  eg cherry-pick -R @ARGV\n";
  }
  die "Unrecognized options: @$opts\n" if @$opts;
  $in = 0 if $in == -1;
  if (!$staged && !$unstaged) {
    $staged = 1;
    $unstaged = 1;
  }

  # Special checks in the case of an incomplete merge to make sure we know
  # what to revert back to; if no --since or --in specified then we can only
  # proceed if the user is only reverting unstaged changes
  if (!@$revs && $staged && -f "$self->{git_dir}/MERGE_HEAD") {
    my @merge_branches = RepoUtil::merge_branches();
    my $list = join(", ", @merge_branches);
    print STDERR <<EOF;
Aborting: Cannot revert the changes since the last commit, since you are in
the middle of a merge and there are multiple last commits.  Please add
  --since BRANCH
to your flags to eg revert, where BRANCH is one of
  $list
If you simply want to abort your merge and undo its conflicts, run
  eg revert --since HEAD
EOF
    exit 1;
  }

  if ($initial_commit) {
    die "Cannot revert a previous commit since there are no previous " .
      "commits.\n" if $in;
    die "Cannot revert to a previous commit since there are no previous " .
        "commits.\n" if !$in && @$revs;
  }

  my @quoted_files = Util::quote_args(@$files);
  my @unmerged_files = `$GIT_CMD ls-files --full-name -u -- @quoted_files`;
  if (@unmerged_files && $in) {
    die "Aborting: please clear conflicts from @unmerged_files before " .
        "proceeding.\n";
  }

  # Record needed information
  $self->{staged} = $staged;
  $self->{unstaged} = $unstaged;
  $self->{just_recent_unstaged} = !$in && !$staged && !@$revs;
  $self->{in} = $in;
  $self->{revs} = "@$revs";
  $self->{revs} = "HEAD" if !@$revs;
  $self->{initial_commit} = $initial_commit;
  if ($in) {
    # Get the revision whose changes we want to revert, and its parents
    Util::push_debug(new_value => 0);
    my $links = ExecUtil::output(
                  "$GIT_CMD rev-list --parents --max-count=1 $self->{revs}");
    Util::pop_debug();
    my @list = split(' ', $links);  # commit id + parent ids

    # Get a symbolic name for the parent revision we will diff against
    my $first_rev = $self->{revs};
    my $parent = $m || 1;
    $first_rev .= "^$parent";

    # Reverting changes in merge commits can only be done against one parent
    die "Cannot revert a merge commit without specifying a parent!\n"
      if !defined($m) && @list > 2;

    # Reverting relative to a parent can only be done with existing parents
    if ($parent + 1 > scalar(@list)) {
      die "Cannot revert the changes made in a commit that has no prior " .
        "commit\n" if !defined($m);
      die "The specified commit does not have $m parents; try a lower " .
        "value for -m\n" if defined($m);
    }

    # The combination of revs to diff between
    $self->{revs} = "$first_rev $self->{revs}";
  }

  # Determine some other stuff needed 
  $self->{files} = \@quoted_files;
  my ($new_files, $newish_files, $revert_files);
  my ($newly_added_files, $new_since_rev_files, $other_files);
  if (!$in && !$initial_commit) {
    my $revision = (@$revs) ? $revs->[0] : "HEAD";
    ($newly_added_files, $new_since_rev_files, $other_files) =
       RepoUtil::get_revert_info($revision, @quoted_files);
  } elsif ($initial_commit) {
    $newly_added_files = $files;
    $new_since_rev_files = [];
    $other_files = [];
  }
  $self->{newly_added_files} = $newly_added_files;
  $self->{new_since_rev_files} = $new_since_rev_files;
  $self->{other_files} = $other_files;
}

sub run {
  my $self = shift;

  my $git_dir = RepoUtil::git_dir();
  my $paths_specified = scalar(@{$self->{files}}) > 0;
  my $ret = 0;

  if (!$self->{in}) {
    my $revision = $self->{revs};
    my @newly_added_files = @{$self->{newly_added_files}};
    my @new_since_rev_files = @{$self->{new_since_rev_files}};
    my @other_files = @{$self->{other_files}};
    my @all_files = @{$self->{files}};

    #
    # Case: Initial commit
    #
    if ($self->{initial_commit}) {
      $ret = ExecUtil::execute("$GIT_CMD rm --cached --quiet -- " .
                               "@newly_added_files", ignore_ret => 1);
      exit $ret if $ret;
    }

    #
    # Set: Reverting both staged and unstaged changes
    #
    elsif ($self->{staged} && $self->{unstaged}) {
      #
      # Case: ALL staged and unstaged changes since some revision
      #
      if (!$paths_specified) {
        if (@newly_added_files) {
          # git reset is not quiet even when requested and has idiotic return
          # state; if three files have conflicts and I try to reset some
          # file other than those three, the command is successful but it
          # spews warnings and gives a bad exit status
          ExecUtil::execute("$GIT_CMD reset -q $revision --" .
                            " @newly_added_files >/dev/null",
                            ignore_ret => 1);
        }

        my ($revision_sha1, $head_sha1, $temp_ret);
        if ($revision ne "HEAD") {
          Util::push_debug(new_value => 0);
          ($temp_ret, $revision_sha1) =
            ExecUtil::execute_captured("$GIT_CMD rev-parse --verify $revision",
                                       ignore_ret => 1);
          ($temp_ret, $head_sha1) =
            ExecUtil::execute_captured("$GIT_CMD rev-parse --verify HEAD",
                                       ignore_ret => 1);
          Util::pop_debug();
        }

        $ret = ExecUtil::execute("$GIT_CMD reset --hard $revision",
                                 ignore_ret => 1);
        exit $ret if $ret;

        if ($revision ne "HEAD" && $revision_sha1 ne $head_sha1) {
          # Note, cannot git reset --soft HEAD, since HEAD has changed in
          # the above reset...
          $ret = ExecUtil::execute("$GIT_CMD reset --soft HEAD\@{1}",
                                   ignore_ret => 1);
          exit $ret if $ret;
        }
      }

      #
      # Case: Selected staged and unstaged changes since some revision
      #
      if ($paths_specified) {
        if (@newly_added_files) {
          # See rant above about 'git reset is not quiet even when requested'
          ExecUtil::execute("$GIT_CMD reset -q $revision --" .
                            " @newly_added_files >/dev/null",
                            ignore_ret => 1);
        }
        if (@new_since_rev_files) {
          # Ugh, when --quiet doesn't actually mean "quiet".
          # (Reproduce with git-1.6.0.6 on incomplete merge handling testcase)
          $ret = ExecUtil::execute("$GIT_CMD rm --quiet --force " .
                                   "--ignore-unmatch -- @new_since_rev_files" .
                                   " > /dev/null",
                                   ignore_ret => 1);
          exit $ret if $ret;
        }
        if (@other_files) {
          $ret = ExecUtil::execute("$GIT_CMD checkout $revision -- " .
                                   "@other_files", ignore_ret => 1);
          exit $ret if $ret;
        }
      }
    }

    #
    # Set: Reverting just staged changes
    #
    elsif ($self->{staged}) {
      if ($paths_specified) {
        $ret = ExecUtil::execute("$GIT_CMD reset -q $revision -- @all_files",
                                 ignore_ret => 1);
        exit $ret if $ret;
      } else {
        $ret = ExecUtil::execute("$GIT_CMD read-tree $revision",
                                 ignore_ret => 1);
        exit $ret if $ret;
      }
    }

    #
    # Set: Reverting just unstaged changes
    #
    elsif ($self->{unstaged}) {
      if ($self->{just_recent_unstaged}) {
        die "Assertion failed: Paths not specified.\n" if (!$paths_specified);
        $ret = ExecUtil::execute("$GIT_CMD checkout -- @all_files",
                                 ignore_ret => 1);
        exit $ret if $ret;
      }
      else {
        if (@newly_added_files) {
          # This results in a no-op essentially, but at least it shows the
          # equivalent commands when no new_since_rev_files and no other_files
          push(@other_files, @newly_added_files);
        }

        if (@new_since_rev_files) {
          $ret = ExecUtil::execute("rm -f @new_since_rev_files",
                                   ignore_ret => 1);
          exit $ret if $ret;
        }

        if (@other_files || !$paths_specified) {
          my ($tmp_index) = Util::quote_args("$git_dir/tmp_index");
          my $git_index = "GIT_INDEX_FILE=$tmp_index ";

          my $cf = "@other_files";
          if (!$paths_specified) {
            my ($cur_dir, $top_dir, $git_dir) = RepoUtil::get_dirs();
            ($cf) = Util::reroot_paths__from_to_files($top_dir, $cur_dir, '.');
          }
          $ret = ExecUtil::execute("$git_index $GIT_CMD checkout $revision " .
                                   "-- $cf", ignore_ret => 1);
          exit $ret if $ret;

          $ret = ExecUtil::execute("rm $tmp_index");
          exit $ret if $ret;
        }
      }
    }
  }

  if ($self->{in}) {
    # Must do unstaged changes first, or extra unknown files can "appear"
    my $location_flag;
    $location_flag = ""         if $self->{unstaged};
    $location_flag = "--cached" if $self->{staged};
    $location_flag = "--index"  if ($self->{staged} && $self->{unstaged});

    my @files = @{$self->{files}};
    my $marker = "";
    $marker = "-- " if (@files);

    my ($cur_dir, $top_dir, $git_dir) = RepoUtil::get_dirs();

    my @diff_flags = ("--binary");
    my @apply_flags = ("--whitespace=nowarn", "--reject");
    push(@apply_flags, $location_flag) if $location_flag;

    # Print out the (nearly) equivalent commands if the user asked for
    # debugging information
    if ($DEBUG) {
      print "    >>Running: " .
            "$GIT_CMD diff @diff_flags $self->{revs} ${marker}@files | ";
      print "(cd $top_dir && " if ($top_dir ne $cur_dir);
      print "$GIT_CMD apply @apply_flags -R";
      print ")" if ($top_dir ne $cur_dir);
      print "\n";
    }

    # Sadly, using "git diff... | git apply ... -R" doesn't quite work,
    # because apply complains very loudly if the diff is empty.  So,
    # we have to run diff, slurp in its output, check if its nonempty,
    # and then only pipe that output back out to git apply if we have
    # an actual diff to revert.
    if ($DEBUG < 2) {
      open(DIFF, "$GIT_CMD diff @diff_flags $self->{revs} ${marker}@files |");
      my @output = <DIFF>;
      my $diff = join("", @output);
      # Listing unmerged paths doesn't count as nonempty
      $diff =~ s/\* Unmerged path.*\n//g;
      close(DIFF);
      $ret = $?;
      exit $ret >> 8 if $ret;

      if ($diff) {
        chdir($top_dir) if $top_dir ne $cur_dir;
        open(APPLY, "| $GIT_CMD apply @apply_flags -R");
        print APPLY $diff;
        close(APPLY);
        chdir($cur_dir) if $top_dir ne $cur_dir;
      }
    }
  }

  return 0;
}

###########################################################################
# rm                                                                      #
###########################################################################
package rm;
@rm::ISA = qw(subcommand);
INIT {
  $COMMAND{rm} = {
    extra => 1,
    section => 'modification',
    about => 'Remove files from subsequent commits and the working copy'
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(git_repo_needed => 1, @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg rm [-f] [-r] [--staged] FILE...

Description:
  Marks the contents of the specified files for removal from the next
  commit.  Also removes the given files from the working copy, unless
  otherwise specified with the --staged flag.

  To prevent data loss, the removal will be aborted if the file has
  modifications.  This check can be overriden with the -f flag.

Examples:
  Mark the content of the files foo and bar for removal from the next
  commit, and delete these files from the working copy.
      \$ eg rm foo bar

  Mark the content of the file baz.c for removal from the next commit, but
  keep baz.c in the working copy as an unknown file.
      \$ eg rm --staged baz.c

  (Advanced) Remove all *.txt files under the Documentation directory OR
  any of its subdirectories.  Note that the asterisk must be preceded with
  a backslash to prevent standard shell expansion.  (Google for 'shell
  expansion' if that makes no sense to you.)
      \$ eg rm Documentation/\\*.txt

Options:
  -f
    Override the file-modification check.

  -r
    Allow recursive removal when a directory name is given.  Without this
    option attempted removal of directories will fail.

  --staged
    Only remove the files from the staging area (the area with changes
    marked as ready to be recorded in the next commit; see 'eg help topic
    staging' for more details).  When using this flag, the given files will
    not be removed from the working copy and will instead become
    \"unknown\" files.

  --
    This option can be used to separate command-line options from the list
    of files, (useful when filenames might be mistaken for command-line
    options).
";
  $self->{'differences'} = '
  eg rm is identical to git rm except that it accepts --staged as a synonym
  for --cached.
';
  return $self;
}

sub preprocess {
  my $self = shift;

  return if (scalar(@ARGV) > 0 && $ARGV[0] eq "--");
  my $result = main::GetOptions("--help" => sub { $self->help() });

  foreach my $i (0..$#ARGV) {
    $ARGV[$i] = "--cached" if $ARGV[$i] eq "--staged";
  }
}

###########################################################################
# squash                                                                  #
###########################################################################
package squash;
@squash::ISA = qw(subcommand);
INIT {
  $COMMAND{squash} = {
    new_command => 1,
    extra => 1,
    section => 'modification',
    about => 'Combine all changes since a given revision into a new commit'
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(git_repo_needed => 1, git_equivalent => '', @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg squash [--against REVISION]

Description:
  Combines all commits since REVISION into a single commit, and open an
  editor with the concatenation of log messages for the user to edit to
  create a new log message.

  REVISION must be an ancestor of the current commit.  If REVISION is
  not specified, the remote tracking branch for the current branch is
  assumed.  (If there is no such branch, eg squash will abort with an
  error.)

Examples:
  Combine all commits in the current branch that aren't in origin/master
  into a single commit
      \$ eg squash --against origin/master

Options:
  --against
    An optional command line argument that makes it clearer what is
    happening.  (In the example above, we are not \"squashing origin/master\",
    we are squashing all changes since origin/master on top of origin/master.
";
  $self->{'differences'} = '
  eg squash is a command new to eg that is not part of git.
';
  return $self;
}

sub preprocess {
  my $self = shift;

  my $since;
  my $result = main::GetOptions(
    "--help"    => sub { $self->help() },
    "against=s" => sub { $since=$_[1] },
    );
  $since = shift @ARGV if !defined($since);
  die "Aborting: Too many revisions specified.\n" if @ARGV > 1;
  if (!defined($since)) {
    my $branch = RepoUtil::current_branch();
    die "Aborting: No revision specified.\n" if !defined($branch);
    my $merge_remote = RepoUtil::get_config("branch.$branch.remote");
    my $merge_branch = RepoUtil::get_config("branch.$branch.merge");
    die "Aborting: No revision specified.\n" if !defined($merge_branch);
    $merge_branch =~ s#^refs/heads/##;
    $since = "$merge_remote/$merge_branch";
  }

  $self->{since} = $since;

  Util::push_debug(new_value => 0);
  my ($retval, $orig_head, $since_sha1sum);

  # Get the sha1sum where HEAD points now, make sure HEAD is valid
  ($retval, $orig_head) =
    ExecUtil::execute_captured("$GIT_CMD rev-parse HEAD", ignore_ret => 1);
  die "Aborting: You have no commits on HEAD.\n" if $retval != 0;
  chomp($orig_head);
  $self->{orig_head} = $orig_head;

  # Get the sha1sum where $since points now, make sure it is valid
  ($retval, $since_sha1sum) =
    ExecUtil::execute_captured("$GIT_CMD rev-parse $self->{since}",
                               ignore_ret => 1);
  die "Invalid revision reference: $self->{since}\n" if $retval != 0;
  chomp($since_sha1sum);

  # Make sure user has no staged changes
  my $output = `$GIT_CMD diff --cached --quiet`;
  die "Aborting: You have staged changes; please commit them first.\n" if $?;

  # Ensure $self->{since} is an ancestor of HEAD
  my $command = "$GIT_CMD rev-list HEAD..$self->{since} | wc -l";
  my ($ret, $unique_to_since) = ExecUtil::execute_captured($command);
  die "Couldn't parse '$command' output '$unique_to_since'"
    unless ($unique_to_since =~ /^\s*([0-9]+)$/);
  my $need_commits = $1;
  die "Aborting: $self->{since} is not an ancestor of HEAD.\n" if $need_commits;
  die "Aborting: There are no commits since $self->{since}.\n"
    if $orig_head eq $since_sha1sum;

  Util::pop_debug();
}

sub run {
  my $self = shift;

  # Fill out a basic log message
  my ($fh, $filename) = main::tempfile();
  print $fh <<EOF;
# Please combine the following commit messages into a single commit message.
# Lines starting with a '#' will be ignored.

EOF
  close($fh);
  my $ret = ExecUtil::execute("$GIT_CMD log --reverse --no-merges --pretty=format:" .
            "'#commit %H%n#Author: %an <%ae>%n#Date:   %ad%n%n%s%n%n%b' " .
            " $self->{since}..$self->{orig_head} >> $filename");
  exit $ret if $ret;

  # Now, reset and commit
  $ret = ExecUtil::execute("$GIT_CMD reset --soft $self->{since}");
  exit $ret if $ret;
  $ret = ExecUtil::execute("$GIT_CMD commit -F $filename --edit",
                           ignore_ret => 1);

  # Restore the branch pointer if the commit failed (e.g. empty log message)
  ExecUtil::execute("$GIT_CMD reset --soft $self->{orig_head}") if $ret != 0;

  unlink($filename);
  return 0;
}

###########################################################################
# stage                                                                   #
###########################################################################
package stage;
@stage::ISA = qw(subcommand);
INIT {
  $COMMAND{stage} = {
    new_command => 1,
    section => 'modification',
    about => 'Mark content in files as being ready for commit'
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(git_repo_needed => 1,
                                git_equivalent => 'add',
                                @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg stage [--] PATH...

Description:
  Marks the contents of the specified files as being ready to commit,
  scheduling them for addition to the repository.  (This is also known as
  staging.)  This step is often not neccessary, since 'eg commit' will fall
  back to unstaged changes if you have not staged anything.  When a
  directory is passed, all files in that directory or any subdirectory are
  recursively added.

  You can use 'eg unstage PATH...' to unstage files.

  See 'eg help topic staging' for more details, including situations where
  you might find staging useful.

Examples:
  Create a new file, and mark it for addition to the repository.
      \$ echo hi > there
      \$ eg stage there

  (Advanced) Mark some changes as good, add some verbose sanity checking code,
  then commit just the good changes.
      Implement some cool new feature in somefile.C
      \$ eg stage somefile.C
      Add some verbose sanity checking code to somefile.C
      Decide to commit the new feature code but not the sanity checking code:
      \$ eg commit --staged

  (Advanced) Show changes in a file, split by those that you have marked as
  good and those that you haven't:
      Make various edits
      \$ eg stage file1 file2
      Make more edits, include some to file1
      \$ eg diff            # Look at all the changes
      \$ eg diff --staged   # Look at the \"ready to be committed\" changes
      \$ eg diff --unstaged # Look at the changes not ready to be commited

Options:
  --
    This option can be used to separate command-line options from the list
    of files, (useful when filenames might be mistaken for command-line
    options).
";
  $self->{'differences'} = '
  eg stage is a command new to eg that is not part of git (update: it is
  part of newer versions of git, with identical meaning to eg).  eg stage
  merely calls git add.
';
  return $self;
}

sub run {
  my $self = shift;

  @ARGV = Util::quote_args(@ARGV);
  return ExecUtil::execute("$GIT_CMD add @ARGV", ignore_ret => 1);
}

###########################################################################
# stash                                                                   #
###########################################################################
package stash;
@stash::ISA = qw(subcommand);
INIT {
  $COMMAND{stash} = {
    section => 'timesavers',
    about => 'Save and revert local changes, or apply stashed changes',
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(
    git_repo_needed => 1,
    initial_commit_error_msg => "Error: Cannot stash away changes when there " .
                                "is no commit yet.",
    @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg stash list [--details]
  eg stash [save DESCRIPTION]
  eg stash apply [DESCRIPTION]
  eg stash show [OPTIONS] [DESCRIPTION]
  eg stash (drop [DESCRIPTION] | clear)

Description:
  This command can be used to remove any changes since the last commit,
  stashing these changes away so they can be reapplied later.  It can also
  be used to apply any previously stashed away changes.  This command can
  be used multiple times to have multiple sets of changes stashed away.

  Unknown files (files which you have never run 'eg stage' on) are
  unaffected; they will not be stashed away or reverted.

  When no arguments are specified to eg stash, the current changes are
  saved away with a default description.

  WARNING: Using the default description can be a bad idea if you will not
  be reapplying the stash very soon.  The default description provided for
  you is based on the commit message of the most recent commit, which has
  confused some users into believing that they have already incorporated
  changes from a stash and throwing the stash away (something that can be
  recovered from, but which involves some sleuthing and low-level commands
  like git-fsck and git-cat-file).

Examples:
  You have lots of changes that you're working on, then get an important
  but simple bug report.  You can stash away your current changes, fix the
  important bug, and then reapply the stashed changes:
      \$ eg stash
      fix, fix, fix, build, test, etc.
      \$ eg commit
      \$ eg stash apply

  You can provide a description of the changes being stashed away, and
  apply previous stashes by their description (or a unique substring of the
  description).
      make lots of changes
      \$ eg stash save incomplete refactoring work
      work on something else that you think will be a quick fix
      \$ eg stash save longer fix than I thought
      fix some important but one-liner bug
      \$ eg commit
      \$ eg stash list
      \$ eg stash apply incomplete refactoring work
      finish off the refactoring
      \$ eg commit
      \$ eg stash apply fix than I
      etc., etc.

  You want to get some details about an existing stash created above:
      \$ eg stash show incomplete refactoring
      \$ eg stash show -p incomplete refactoring

Options:
  list [--details]
    Show the saved stash descriptions.  If the --details flag is present,
    provide more information about each stash.

  save DESCRIPTION
    Save current changes with the description DESCRIPTION.  The
    description cannot start with \"-\".

  apply [DESCRIPTION]
    Apply the stashed changes with the specified description.  If no
    description is specified, and more than one stash has been saved, an
    error message will be shown.  The description cannot start with \"-\".

  show [OPTIONS] [DESCRIPTION]
    Show the stashed changes with the specified description.  If no
    description is specified, and more than one stash has been saved, an
    error message will be shown.  The description cannot start with \"-\".

    Note that the output shown is the output from diff --stat.  If you
    want the full patch, pass the -p option.  Other options for
    controlling diff output (such as --name-status or --dirstat, see
    'git help diff') are also possible options.

  drop [DESCRIPTION]
    Delete the specified stash.  The description cannot start with
    \"-\".

  clear
    Delete all stashed changes.
";
  $self->{'differences'} = '
  eg stash is only cosmetically different than git stash, and is fully
  backwards compatible.

  eg stash list, by default, only shows the saved description -- not
  the reflog syntax or branch the change was made on.

  eg stash apply and eg stash show also accept any string and will
  apply or show the stash whose description contains that string.
  Although stash and apply accept reflog syntax (like their git stash
  counterparts), i.e. while
      $ eg stash apply stash@{3}
  will work, I think it will be easier for the user to run
      $ eg stash apply rudely interrupted changes
';
  return $self;
}

sub preprocess {
  my $self = shift;
  my $package_name = ref($self);

  #
  # Parse options
  #
  my @args;
  if (scalar(@ARGV) > 0 && $ARGV[0] ne "--") {
    main::GetOptions("--help" => sub { $self->help() });
  }

  # Get the (sub)subcommand
  if (scalar @ARGV == 0) {
    $self->{subcommand} = 'save';
  } elsif ($ARGV[0] eq "--") {
    $self->{subcommand} = "save";
  } else {
    $self->{subcommand} = shift @ARGV;
    if ($self->{subcommand} eq '-k') {
      $self->{subcommand} = "save";
      unshift @ARGV, '-k';
    }
    push(@args, $self->{subcommand});

    # Pass all flags on to git
    while(@ARGV > 0 && $ARGV[0] =~ /^-/ && $ARGV[0] !~ /^--$/) {
      if ($self->{subcommand} eq 'list' && $ARGV[0] eq '--refs') {
        $self->{show_refs} = 1;
        shift @ARGV;
      } elsif ($self->{subcommand} eq 'list' && $ARGV[0] eq '--details') {
        $self->{show_details} = 1;
        shift @ARGV;
      } else {
        push(@args, shift @ARGV);
      }
    }
    if ($self->{subcommand} eq 'branch') {
      push(@args, shift @ARGV);  # Pull off the branch name
    }
  }

  # Show a help message if they picked a bad stash subaction.
  my @valid_commands = qw(list show apply clear save drop pop branch create);
  if (! grep {$_ eq $self->{subcommand}} @valid_commands) {
    print STDERR<<EOF;
Aborting; invalid stash subcommand: $self->{subcommand}
EOF
    exit 1;
  }

  # Translate the description passed to apply or show into a reflog reference
  my @commands_accepting_existing_stash = qw(show drop pop apply branch);
  if ((grep {$_ eq $self->{subcommand}} @commands_accepting_existing_stash) &&
      scalar @ARGV > 0) {
    my $stash_description = "@ARGV";
    @ARGV = ();
    if ($stash_description =~ m#^stash\@{[^{]+}$#) {
      push(@args, $stash_description)
    } else {
      # Will need to compare arguments to existing stash descriptions...
      print "  >>Getting stash descriptions to compare to arguments:\n"
        if $DEBUG;
      my ($retval, $output) =
        ExecUtil::execute_captured("$EG_EXEC stash list --refs");
      my @lines = split('\n', $output);
      my %refs;
      my %bad_refs;
      while (@lines) {
        my $desc = shift @lines;
        my $ref = shift @lines;
        $bad_refs{$desc}++ if defined $refs{$desc};
        $refs{$desc} = $ref;
      }

      # See if the stash description matches zero, one, or more existing
      # stash descriptions; convert it to a reflog entry if only one
      my @matches = grep {$_ =~ m#\Q$stash_description\E#} (keys %refs);
      if (scalar @matches == 0) {
        die "No stash matching '$stash_description' exists!  Aborting.\n";
      } elsif (scalar @matches == 1) {
        # Only one regex match; use it
        $stash_description = $matches[0];
      } else {
        # See if our string matches one stash description exactly; if so,
        # we can use it.
        if (!grep {$_ eq $stash_description} (keys %refs)) {
          die "Stash description '$stash_description' matches multiple " .
              "stashes:\n  " . join("\n  ", @matches) . "\n" .
              "Aborting.\n";
        }
      }
      die "Stash description '$stash_description' matches multiple stashes.\n"
        if $bad_refs{$stash_description};

      push(@args, $refs{$stash_description});
    }
  }

  # Add any unprocessed args to the arguments to use
  push(@args, @ARGV);

  # Reset @ARGV with the built up list of arguments
  @ARGV = @args;
}

sub run {
  my $self = shift;
  my $package_name = ref($self);
  my $ret;

  @ARGV = Util::quote_args(@ARGV);
  if ($self->{subcommand} eq 'list') {
    my $output = "";
    open($OUTFH, '>', \$output) ||
      die "eg $package_name: cannot open \$OUTFH: $!";

    $ret = ExecUtil::execute("$GIT_CMD $package_name @ARGV", ignore_ret => 1);

    my @lines = split('\n', $output);
    my $regex = 
      qr#(stash\@{[^}]+}): (?:WIP )?[Oo]n [^:]*: (?:[0-9a-f]+\.\.\. )?#;
    foreach my $line (@lines) {
      if ($self->{show_details}) {
        print "$line\n";
      } else {
        $line =~ s/$regex//;
        print "$line\n";
        print "$1\n" if $self->{show_refs};
      }
    }
  } else {
    $ret = ExecUtil::execute("$GIT_CMD $package_name @ARGV", ignore_ret => 1);
  }
  return $ret;
}

###########################################################################
# status                                                                  #
###########################################################################
package status;
@status::ISA = qw(subcommand);
INIT {
  $COMMAND{status} = {
    section => 'discovery',
    about => 'Summarize current changes'
    };
  $ALIAS{'st'} = "status";
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(git_repo_needed => 1, @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg status

Description:
  Show the current state of the project.  In addition to showing the
  currently active branch, whether you have unpushed local commits,
  whether you have stashed any sets of changes away (see 'eg help
  stash'), this command will list files with content in any of the
  following states:

     Unknown files
       Files that are not explicitly ignored (i.e. do not appear in an
       ignore list such as a .gitignore file) but whose contents are still
       not tracked by git.

       These files can become known by running 'eg stage FILENAME', or
       ignored by having their name added to a .gitignore file.

     Newly created unknown files
       Same as unknown files; the reason for splitting unknown files into
       two sets is to make it easier to find the files users are more
       likely to want to add.  Also, 'eg commit' will by default error out
       with a warning message if there are any newly created unknown files
       in order to prevent forgetting to add files that should be included
       in a commit.

     Modified submodules:
       subdirectories that are tracked under their own git repository, and
       that are being tracked via use of the 'git submodule' command.

     Changed but not updated (\"unstaged\")
       Files whose contents have been modified in the working copy.

       (Advanced usage note) If you explicitly mark all the changes in a
       file as ready to be committed, then the file will not appear in this
       list and will instead appear in the \"staged\" list (see below).
       However, a file can appear in both the unstaged and staged lists if
       only part of the changes in the file are marked as ready for commit.

     Unmerged paths (files with conflicts)
       Files which could not be automatically merged.  If such files are
       text files, they will have the typical conflict markers.  These
       files need to be manually edited to give them the correct contents,
       and then the user should inform git that the conflicts are resolved
       by running 'eg resolved FILENAME'.

     Changes ready to be committed (\"staged\")
       Files with content changes that have explicitly been marked as ready
       to be committed.  This state only typically appears in advanced
       usage.

       Files enter this state through the use of 'eg stage'.  Files can
       return to the unstaged state by running 'eg unstage' See 'eg help
       topic staging' to learn about the staging area.

";
  $self->{'differences'} = "
  eg status output is essentially just a streamlined and cleaned version of
  git status output, with the addition of a new section (newly created
  untracked files) and an extra status message being displayed when in the
  middle of a special state (am, bisect, merge, or rebase).

  The streamlining serves to avoid information overload to new users (which
  is only possible with a less error prone \"commit\" command) and the
  cleaning (removal of leading hash marks) serves to make the system more
  inviting to new users.

  A slight wording change was done to transform \"untracked\" to \"unknown\"
  since, as Havoc pointed out, the word \"tracked\" may not be very self
  explanatory (in addition to the real meaning, users might think of:
  \"tracked in the index?\", \"related to remote tracking branches?\", \"some
  fancy new monitoring scheme unique to git that other vcses do not have?\",
  \"is there some other meaning?\").  I do not know if \"known\" will fully
  solve this, but I suspect it will be more self-explanatory than
  \"tracked\".

  There are also slight changes to the section names to reinforce
  consistent naming when referring to the same concept (staging, in this
  case), but the changes are very slight.

  The extra status message when in the middle of an am, bisect, merge,
  or rebase serves two purposes: to remind users that they are in the
  middle of some operation (some people don't use the special prompt
  from git's bash-completion support), and to provide a command users
  can run to get help resolving such situations.  (Many users were
  confused about or unaware how to resolve incomplete merges and
  rebases; providing them with a specially written help page they
  could access seemed to effectively assist them figure out the
  appropriate steps to take -- especially in tricky or special cases.)
";
  return $self;
}

sub preprocess {
  my $self = shift;

  my @old_argv = @ARGV;
  my $no_filter = 0;
  Getopt::Long::Configure("permute");
  my $result = main::GetOptions(
    "help"      => sub { $self->help() },
    "short|s"   => sub { $no_filter = 1 },
    "porcelain" => sub { $no_filter = 1 },
    "z"         => sub { $no_filter = 1 },
    );
  @ARGV = @old_argv;
  $self->{no_filter} = $no_filter;
}

sub run {
  my $self = shift;

  -t STDOUT and $ENV{"GIT_PAGER_IN_USE"}=1;
  return $self->SUPER::run() if $self->{no_filter};

  $self->{special_state} = RepoUtil::get_special_state($self->{git_dir});

  @ARGV = Util::quote_args(@ARGV);
  return ExecUtil::execute("$GIT_CMD status @ARGV", ignore_ret => 1);
}

sub postprocess {
  my $self = shift;
  my $output = shift;

  # If we can't parse the git status output, what we tell the user...
  my $workaround_msg =
    "You'll need to use an older git or a newer eg or 'git status'.";

  if ($DEBUG == 2) {
    print "    >>(No commands to run, just data to print)<<\n";
    return;
  }

  if ($self->{no_filter}) {
    print $output;
    return;
  }

  my $branch;
  my $initial_commit = 0;
  my @sections;
  my %files;
  my %section_mapping = (
       'Untracked files:' => 'Unknown files:',
       'Changes to be committed:' => 'Changes ready to be committed ("staged"):',
       'Changed but not updated:' => 'Changed but not updated ("unstaged"):',
       'Unmerged paths:' => 'Unmerged paths (files with conflicts):'
       );

  my @basic_info;
  my @diff_info;

  # Exit early if git status had an error
  if ($output =~ m/^fatal:/) {
    print STDERR $output;
    exit 128;
  }

  # Parse the output
  my @lines = split('\n', $output);
  my $cur_state = -1;
  while (@lines) {
    my $line = shift @lines;
    my $section = undef;
    my $title;

    if ($line =~ m/^# On branch (.*)$/) {
      $branch = $1;
    } elsif ($line =~ m/^# Initial commit$/) {
      $initial_commit = 1;
    } elsif ($line =~ m/^# ([A-Z].*:)$/) {
      $cur_state = 1;
      $title = $section_mapping{$1} || $1;
      $section = $title;
    } elsif ($cur_state < 0) {
      next if $line !~ m/^# (.+)/;
      push(@basic_info, $1);
    } elsif ($line =~ m/^no changes added to commit/ ||
             $line =~ m/^# Untracked files not listed/) {
      next;  # Skip this line
    } elsif ($line =~ m#^(?:\e\[.*?m)?diff --git a/#) {
      push(@diff_info, $line);
      push(@diff_info, @lines);
      last;
    } else {
      die "ERROR: Cannot parse git status output.\n" .
          "$workaround_msg\n" .
          "Remaining unparsed lines:\n$line\n" . join("\n", @lines) . "\n";
    }

    # If we're inside a section type, parse it
    if ($cur_state > 0) {
      push (@sections, $section);
      my @section_files;
      my $hints;

      # Parse the hints first
      $line = shift @lines;
      while ($line =~ m/^#\s+\(use ".*/) {
        $hints .= $line;
        $line = shift @lines;
      }
      die("Bug parsing git status output.\n$workaround_msg\n") if $line ne '#';
      $line = shift @lines; # Get rid of blank line

      while (defined $line && $line =~ m/^(?:\e\[.*?m)?#.+$/) {
        if ($line =~ m/^(?:\e\[.*?m)?#(\s+)(.*)/) {
          my $space = $1;
          my $file = $2;

          # Remove leading space character for submodule changes
          # (There's no real reason to do this other than laziness in
          # updating test file results; output looks fine either way.)
          $space =~ s/^[ ]//;
          # Workaround the file not have proper terminating color escape sequence
          if ($file =~ /^\s*\e\[.*?m/ && $file !~ /\e\[m$/) {
            $file .= "\e[m";
          }
          push @section_files, "$space$file";
        }
        $line = shift @lines;
        unshift(@lines, $line) if $line && $line =~ m#^(?:\e\[.*?m)?diff --git a/#;
      }

      if (defined($files{$section})) {
        push(@{$files{$section}{'file_list'}}, @section_files);
      } else {
        $files{$section} = { title     => $title, # may be undef
                             hint      => $hints,
                             file_list => \@section_files };
      }

      # Record that we finished parsing this section
      $cur_state = 0;
    }
  }

  # Split the unknown files into those that are newly created and those that
  # have been around
  if (defined($files{'Unknown files:'})) {
    # Get the list of unknown files that have been around for a while
    my ($cur_dir, $top_dir, $git_dir) = RepoUtil::get_dirs();
    my %old_unknown;
    if (-f "$git_dir/info/ignored-unknown") {
      my @old_unknown_files = `cat "$git_dir/info/ignored-unknown"`;
      chomp(@old_unknown_files);
      @old_unknown_files =
        Util::reroot_paths__from_to_files($top_dir, $cur_dir, @old_unknown_files);
      map { $old_unknown{$_} = 1 } @old_unknown_files;
    }

    my @new_unknowns;
    my @old_unknowns;
    foreach my $fileline (@{$files{'Unknown files:'}{'file_list'}}) {
      $fileline =~ m#(\s+(?:\e\[.*?m)?)(.*?)((?:\e\[m)?)$# ||
        die "Failed parsing git status output: '$fileline'\n$workaround_msg\n";
      if ($old_unknown{$2}) {
        push(@old_unknowns, $fileline);
      } else {
        push(@new_unknowns, $fileline);
      }
    }

    my ($index) = grep $sections[$_] eq "Unknown files:", 0 .. $#sections;
    splice(@sections, $index, 1);
    if (@new_unknowns) {
      $files{'new_unknowns'} = { title     => 'Newly created unknown files:',
                                 file_list => \@new_unknowns };
      splice(@sections, $index++, 0, 'new_unknowns');
    }
    if (@old_unknowns) {
      $files{'old_unknowns'} = { title     => 'Unknown files:',
                                 file_list => \@old_unknowns };
      splice(@sections, $index, 0, 'old_unknowns');
    }
  }

  # Print out the branch we are on
  if (defined $branch) {
    print "(On branch $branch";
    print ", no commits yet" if $initial_commit;
    print ")\n";
  }
  foreach my $line (@basic_info) {
    print "($line)\n";
  }
  my ($retval, $num_stashes) =
      ExecUtil::execute_captured("$GIT_CMD stash list | wc -l");
  chomp($num_stashes);
  if ($num_stashes > 0) {
    print "(You have $num_stashes stash(es).  Use 'eg stash list' to see them.)\n";
  }

  # Print out info about any special state we're in
  my $notice = "";
  if (defined $self->{special_state}) {
    my ($highlight, $reset) = ("", "");
    if (-t STDOUT) {
      $highlight=`$GIT_CMD config --get-color color.status.header "red reverse"`;
      $reset=`$GIT_CMD config --get-color "" "reset"`;
    }

    $notice .= "($highlight";
    $notice .= "YOU ARE IN THE MIDDLE OF A $self->{special_state}; ";
    $notice .= "RUN 'eg help topic middle-of-";
    if ($self->{special_state} eq "APPLY MAIL OR REBASE") {
      # FIXME: How do we get into this state anyway, and what should they run?
      # Well, printing nothing will just get them the general topic page, then
      # they can pick between am and rebase
    } elsif ($self->{special_state} =~ /REBASE$/) {
      $notice .= "rebase";
    } elsif ($self->{special_state} eq "APPLY MAIL") {
      $notice .= "am";
    } elsif ($self->{special_state} eq "MERGE") {
      $notice .= "merge";
    } elsif ($self->{special_state} eq "BISECT") {
      $notice .= "bisect";
    }
    $notice .= "' FOR MORE INFO.";
    $notice .= "$reset)\n";
    print $notice;
  }

  # Print out all the various changes
  my $linecount = 0;
  foreach my $section (@sections) {
    if (defined($files{$section})) {
      print "$files{$section}{'title'}\n";
      $linecount += 1;
      foreach my $fileline (@{$files{$section}{'file_list'}}) {
        print "$fileline\n";
        $linecount += 1;
      }
    }
  }

  # Repeat the notice so users will see it
  if (defined $self->{special_state} && $linecount > 0) {
    print $notice;
  }

  # Print the diff if we're running with the -v option
  print join("\n", @diff_info)."\n" if (@diff_info);
}

###########################################################################
# switch                                                                  #
###########################################################################
package switch;
@switch::ISA = qw(subcommand);
INIT {
  $COMMAND{switch} = {
    new_command => 1,
    section => 'projects',
    about => 'Switch the working copy to another branch'
    };
  $ALIAS{'sw'} = "switch";
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(
    git_repo_needed => 1,
    git_equivalent => 'checkout',
    initial_commit_error_msg => "Error: Cannot create or switch branches " .
                                "until a commit has been made.",
    @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg switch BRANCH
  eg switch REVISION

Description:
  Switches the working copy to another branch, or to another tag or
  revision.  (Switch is an operation that can be done locally, without any
  network connectivity).

  To list, create, or delete branches to switch to, use eg branch.  To
  list, create, or delete tags to switch to, use eg tag.  To list, create,
  or delete revisions, use eg log, eg commit, or eg reset, respectively.
  :-)

Examples:
  Switch to the 4.8 branch
      \$ eg switch 4.8

  Switch the working copy to the v4.3 tag
      \$ eg switch v4.3

";
  $self->{'differences'} = '
  eg switch is a subset of the functionality of git checkout; the abilities
  and flags for creating and switching branches are identical between the
  two, just the name of the function is different.

  The ability of git checkout to get older versions of files is not part of
  eg switch; instead that ability can be found with eg revert.
';
  return $self;
}

sub preprocess {
  my $self = shift;

  if (scalar(@ARGV) == 0) {
    print STDERR<<EOF;
No branch (or revision) to switch to specified!  See the help for eg switch
and eg branch.  The following branches exist, with the current branch marked
with an asterisk:

EOF
    my $branch_obj = "branch"->new();
    $branch_obj->run();
    exit 1;
  }

  # Don't let them try to use eg switch to check out older revisions of files;
  # this is just supposed to be a subset of git checkout
  if (!grep {$_ =~ /^-/} @ARGV) {
    die "Invalid arguments to eg switch: @ARGV\n" if @ARGV > 1;
    Util::push_debug(new_value => 0);
    my $valid_ref = RepoUtil::valid_ref($ARGV[0]);
    Util::pop_debug();
    die "Invalid branch/revision reference: $ARGV[0]\n" if !$valid_ref;
  }

  $self->SUPER::preprocess();
}

sub run {
  my $self = shift;

  @ARGV = Util::quote_args(@ARGV);
  return ExecUtil::execute("$GIT_CMD checkout @ARGV", ignore_ret => 1);
}

###########################################################################
# tag                                                                     #
###########################################################################
package tag;
@tag::ISA = qw(subcommand);
INIT {
  $COMMAND{tag} = {
    unmodified_behavior => 1,
    extra => 1,
    section => 'modification',
    about => 'Provide a name for a specific version of the repository'
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(git_repo_needed => 1, @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg tag TAG [REVISION]
  eg tag -d TAG

Description:
  Create or delete a tag (i.e. a nickname) for a specific version of the
  project.  (Tags can also be annotated or digitally signed; see the 'See
  Also section.)

  Note that tags are local; creation of tags in a remote repository can be
  accomplished by first creating a local tag and then pushing the new tag
  to the remote repository using eg push.

Examples
  List the available local tags
      \$ eg tag

  Create a new tag named good-version for the last commit.
      \$ eg tag good-version

  Create a new tag named version-2.0.3 for 3 versions before the last commit
  (assuming one is on a branch named project-2.0)
      \$ eg tag version-2.0.3 project-2.0~3

  Delete the tag named gooey
      \$ eg tag -d gooey

  Create a new tag named look_at_me in the default remote repository
      \$ eg tag look_at_me
      \$ eg push --tag look_at_me

Options:
  -d
    Delete the specified tag
";
  return $self;
}

###########################################################################
# track                                                                   #
###########################################################################
package track;
@track::ISA = qw(subcommand);
INIT {
  $COMMAND{track} = {
    new_command => 1,
    extra => 1,
    section => 'projects',
    about => 'Set which remote branch a local branch tracks'
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(git_repo_needed => 1, git_equivalent => '', @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg track (--show [LOCAL_BRANCH] | --show-all)
  eg track [LOCAL_BRANCH] REMOTE_TRACKING_BRANCH
  eg track --unset [LOCAL_BRANCH]

Description:
  eg track helps manage which remote branches your local branches
  track.  Having a local branch track a remote branch means that when
  the local branch is the active branch, that the corresponding remote
  branch is the default push or pull location for eg push or eg pull.

  There are three different things eg track can do, each corresponding to
  one of the usage forms listed above: list which remote branch a local
  branch tracks, make a local branch track some remote branch, or make a
  local branch no longer track any remote branch.

  If LOCAL_BRANCH is not specified, the currently active branch is
  assumed.

Examples:
  Show which remote branches all local branches are tracking
     \$ eg track --show-all

  Show which remote branch the local branch 'stable' tracks
     \$ eg track --show stable

  Make your currently active branch track the 'magic' branch of the 'jim'
  repository (see 'eg help remote' for setting up nicknames like 'jim' for
  remote repositories)
      \$ eg track jim/magic

  Make your branch 'bugfix' track the 'master' branch of the 'origin'
  repository (note that 'origin' is the repository you cloned from, unless
  you've explicitly changed that using the eg remote command or some other
  low-level means):
      \$ eg track bugfix origin/master

  Have your 'random-changes' branch stop tracking any remote branch:
      \$ eg track --unset random-changes
";
  $self->{'differences'} = '
  eg track is unique to eg; git does not have a similar command.
';
  return $self;
}

sub preprocess {
  my $self = shift;

  # Check for the --help arg
  my $mode = "set";
  my ($local_branch, $remote_branch, $remote);
  Getopt::Long::Configure("permute");
  my $result = main::GetOptions(
    "--help"    => sub { $self->help() },
    "show"      => sub { $mode = "show"; },
    "show-all"  => sub { $mode = "show-all"; },
    "unset"     => sub { $mode = "unset"; });

  # Get the remote branch to track, if we're setting up tracking info
  if ($mode eq "set") {
    my ($ret, $remote_tracking_branch);

    # Sanity checks
    die "Error: Too many arguments.  Run 'eg help track'.\n" if (@ARGV > 2);
    die "Error: Insufficient arguments.  Run 'eg help track'.\n" if (@ARGV < 1);

    # Get the remote tracking branch, and sanity check it
    $remote_tracking_branch = pop @ARGV;
    die "Error: Invalid remote tracking branch '$remote_tracking_branch'\n" .
        "Correct format for remote tracking branches is:\n" .
        "  REMOTENAME/REMOTEBRANCHNAME\n" if $remote_tracking_branch !~ '/';

    # Split remote tracking branch into remote name and remote branch name
    ($remote, $remote_branch) = split('/', $remote_tracking_branch, 2);

    # Make sure the remote is a valid name
    Util::push_debug(new_value => 0);
    $ret = ExecUtil::execute("$GIT_CMD remote | grep '^$remote\$' > /dev/null",
                              ignore_ret => 1);
    die "Error: '$remote' is not a valid remote name.\n" .
        "(Use 'eg remote' to find valid remote names).\n" if $ret;
    Util::pop_debug();
  }

  # Get the local branch to operate on
  $local_branch = shift @ARGV;
  if (!$local_branch && $mode ne "show-all") {
    $local_branch = RepoUtil::current_branch();
  }
  if ($local_branch) {
    # Make sure $local_branch is defined and has a valid value
    Util::push_debug(new_value => 0);
    if (!$local_branch || !RepoUtil::valid_ref("refs/heads/$local_branch")) {
      die "Error: The branch '$local_branch' is not (yet) a valid local branch.\n";
    }
    Util::pop_debug();
  }

  $self->{mode} = $mode;
  $self->{branch} = $local_branch;
  if ($mode eq "set") {
    $self->{remote_branch} = "refs/heads/$remote_branch";
    $self->{remote} = $remote
  }
}

sub run {
  my $self = shift;

  my ($ret, $output);
  my ($mode, $branch, $remote_branch, $remote) =
     ($self->{mode}, $self->{branch}, $self->{remote_branch}, $self->{remote});

  if ($mode eq "show-all") {
    $branch = ".*";
    $mode = "show";
  }

  if ($mode eq "show") {
    my %tracking;

    # Get the remote tracking flags
    ($ret, $output) = ExecUtil::execute_captured(
      "$GIT_CMD config --get-regexp '^branch\.$branch\.(remote|merge)'",
      ignore_ret => 1);
    chomp($output);

    # Exit early if we're in --translate mode
    if ($DEBUG == 2) {
      print "    >>(No more commands to run, " .
            "just output to parse and print)<<\n";
    }

    # Check if there are no matches
    if ($ret) {
      my $message = "Branch $branch is not";
      $message = "No branches are" if $branch eq ".*";
      print "$message set to track anything.\n";
      return 0;
    }

    # Fill the %tracking hash
    my @lines = split('\n', $output);
    foreach my $line (@lines) {
      $line =~ /^branch\.(.*)\.(remote|merge) (.*)$/
        or die "Bad output '$line'!\n";

      $tracking{$1}{$2} = $3;
    }

    # Show all the tracking information
    foreach my $bname (sort keys %tracking) {
      my $remote = $tracking{$bname}{'remote'} || "''";
      my $remote_branch = $tracking{$bname}{'merge'} || "''";
      print "Branch $bname tracks $remote_branch of remote $remote.\n";
    }
    return 0;

  } elsif ($mode eq "set") {
    $ret =  ExecUtil::execute(
       "$GIT_CMD config branch.$branch.remote $remote", ignore_ret => 1);
    $ret |= ExecUtil::execute(
       "$GIT_CMD config branch.$branch.merge $remote_branch", ignore_ret => 1);

    if (!$ret && $DEBUG < 2) {
      print "$branch now set to track " .
            "branch $remote_branch of remote $remote.\n";
    }
    return $ret;
  } elsif ($mode eq "unset") {
    ExecUtil::execute(
       "$GIT_CMD config --unset branch.$branch.remote", ignore_ret => 1);
    ExecUtil::execute(
       "$GIT_CMD config --unset branch.$branch.merge", ignore_ret => 1);

    if ($DEBUG < 2) {
      print "$branch no longer tracks any remote branch.\n";
    }
    return 0;
  }
}

###########################################################################
# unstage                                                                 #
###########################################################################
package unstage;
@unstage::ISA = qw(revert);
INIT {
  $COMMAND{unstage} = {
    new_command => 1,
    extra => 1,
    section => 'modification',
    about => 'Mark changes in files as no longer ready for commit'
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(git_repo_needed => 1, git_equivalent => '', @_);
  bless($self, $class);

  unshift(@ARGV, "--") if scalar(@ARGV) > 0 && $ARGV[0] ne "--";
  unshift(@ARGV, "--staged");

  $self->{'help'} = "
Usage:
  eg unstage [--] PATH...

Description:
  Marks the changes in the specified files as not being ready to commit.
  When a directory is passed, all files in that directory or any
  subdirectory are recursively unstaged.

  Note that this command is equivalent to 'eg revert --staged PATH...'

  See 'eg help topic staging' for more details, including situations where
  you might find staging useful.

Examples:
  Create a new file, and mark it for addition to the repository, then change
  your mind
      \$ echo hi > there
      \$ eg stage there
      \$ eg unstage there

  Modify an existing file, mark the modified version as being ready for commit,
  then change your mind
      \$ echo some extra info at end of file >> foo
      \$ eg stage foo
      \$ eg unstage foo
";
  $self->{'differences'} = '
  eg unstage is a command new to eg that is not part of git; it is implemented
  on top of eg revert --staged, though it could as easily simply call through
  to git reset.
';
  return $self;
}

# unstage inherits from revert, and simply modifies @ARGV in new(), so that
# revert will get run with the right arguments

###########################################################################
# update                                                                  #
###########################################################################
package update;
@update::ISA = qw(subcommand);
INIT {
  $COMMAND{update} = {
    new_command => 1,
    extra => 1,
    section => 'compatibility',
    about => 'Use antiquated workflow for refreshing working copy, if safe'
    };
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(
    git_repo_needed => 1,
    git_equivalent => 'pull',
    @_);
  bless($self, $class);
  $self->{'help'} = "
Usage:
  eg update

Description:
  Gets updates from the default remote repository if updating is safe, and
  provides suggestions on proceeding otherwise.

  eg update does not accept any options...other than --help.

Examples:
  Get any updates from the remote repository
      \$ eg update
";
  $self->{'differences'} = '
  eg update is unique to eg; it exists primarily to ease the transition for
  cvs/svn users and to do something useful for them.  In particular, eg
  update is used just to do fast-forward updates when there are no local
  changes; if anything more than this is needed, eg advises users to run
  other commands.

  Here are the special cases eg update detects and provides tailored
  messages for:
    * User has local commits           => ask user to use eg pull instead
    * User provides argument to update => tell user to use eg switch for
                                          checking out an older revision or
                                          eg revert to undo changes to a file
    * User has locally deleted files   => tell user to use eg revert to
                                          undo local changes (and that they do
                                          not need to delete the file first as
                                          they did with cvs)
    * User has local modifications     => Tell user to stash or commit their
                                          changes before pulling updates
    * No default repository to contact => Tell user to run "eg remote add
                                          origin REPOSITORY_URL"
    * branch.BRANCH.merge not set and  => Warn user that we do not know which
      more than one remote branch         branch to pull from and suggest eg
      present                             pull or setting branch.BRANCH.merge
';
  return $self;
}

sub preprocess {
  my $self = shift;

  # Check for the --help arg
  my $result=main::GetOptions("--help" => sub { $self->help() });

  # Abort if the user specified any args other than --help
  if (@ARGV) {
    print STDERR <<EOF;
Aborting: No arguments to update are allowed.  If you are trying to switch
to a different revision, use eg switch.  If you are trying to undo the changes
to a particular file, use eg revert.
EOF
    exit 1;
  }

  # Check if there are local changes
  my $status = RepoUtil::commit_push_checks();
  my $has_changes = $status->{has_staged_changes} ||
    $status->{has_unstaged_changes} || $status->{has_unmerged_changes};
  if ($has_changes) {
    print STDERR <<EOF;
Aborting: You have local changes, and pulling updates could put your
working copy in a nonworking state.  Consider committing your changes
before updating, or using eg stash to stash the changes away and reapply
them after the update.
EOF

    if ($status->{output} =~ /^\s+deleted:/m) {
      print STDERR "\n";
      print STDERR <<EOF;
NOTE: If you are trying to undo the changes in a file, just run
  eg revert FILE
This works whether or not the file has been deleted.
EOF
    }
    
    exit 1;
  }

  if ($DEBUG) {
    print "  >>Commands to determine where to update from:\n";
  }

  # Check if there is a default repository to pull from
  # <This code mostly taken from pull, but "origin" serves as extra backup>
  my $branch = RepoUtil::current_branch() || "HEAD";
  my $repo = RepoUtil::get_default_push_pull_repository();
  $self->{repository} = $repo;
  $self->{local_branch} = $branch;

  # Check if there is a default branch to pull
  my $merge_branch = RepoUtil::get_config("branch.$branch.merge");
  if (!$merge_branch) {
    # Check if the remote repository has exactly 1 branch...if so, return it,
    # otherwise throw an error
    my ($quoted_repo) = Util::quote_args("$self->{repository}");
    my ($ret, $output) = 
      ExecUtil::execute_captured("$GIT_CMD ls-remote -h $quoted_repo");
    if ($ret == 0) {
      my @remote_refs = split('\n', $output);
      if (@remote_refs == 1) {
        # git ls-remote -h output changed at some point to include the sha1sum;
        # we only want the refspec
        if ($remote_refs[0] =~ /^[0-9a-f]+\s+(.*)/) {
          $merge_branch = $1;
        } else {
          $merge_branch = $remote_refs[0];
        }
      }
    }
  }
  if (!$merge_branch) {
    print STDERR <<EOF;
Error: It is not clear which remote branch to update from.
You can either use eg pull instead, or run 
  eg config branch.$branch.merge BRANCHANME
EOF
    exit 1;
  }
  $self->{merge_branch} = $merge_branch;
}

sub run {
  my $self = shift;
  my $package_name = ref($self);

  # Get value to set ORIG_HEAD to (unless we are on the initial commit)
  Util::push_debug(new_value => 0);
  my ($retval, $orig_sha1sum) = 
    ExecUtil::execute_captured("$GIT_CMD rev-parse HEAD", ignore_ret => 1);
  my $has_orig_head = ($retval == 0);
  Util::pop_debug();

  # Do the fetch && reset, making sure to set ORIG_HEAD
  my ($ret, $output) = 
    ExecUtil::execute_captured("$GIT_CMD fetch $self->{repository} " .
                               "$self->{merge_branch}:$self->{local_branch}",
                               ignore_ret => 1);
  if ($output =~ /\[rejected\].*\(non fast forward\)/) {
    die "fatal: Cannot update because you have local commits; " .
        "try 'eg pull' instead.\n";
  } elsif ($ret != 0) {
    die "Error updating (output = $output); please report the bug, and\n" .
        "try using 'eg pull' instead.\n";
  } else {
    $ret = ExecUtil::execute_captured("$GIT_CMD reset --hard " .
                                      "$self->{local_branch}");
    if ($has_orig_head && $DEBUG < 2) {
      open(ORIG_HEAD, "> $self->{git_dir}/ORIG_HEAD");
      print ORIG_HEAD $output;
      close(ORIG_HEAD);
    }
    print "Updated the current branch.\n" if ($DEBUG < 2);
  }
  return $ret;
}

###########################################################################
# version                                                                 #
###########################################################################
package version;
@version::ISA = qw(subcommand);

BEGIN {
  undef *version::new unless $] < 5.010; # avoid name clashing
}

sub new {
  my $class = shift;
  my $self = $class->SUPER::new(git_repo_needed => 0, @_);
  bless($self, $class);
}

# Override help because we don't want to both definining $COMMAND{help}
sub help {
  my $self = shift;

  $self->{'help'} = "
Usage:
  eg version

Description:
  Show the current version of eg.
";

  open(OUTPUT, ">&STDOUT");
  print OUTPUT $self->{'help'};
  close(OUTPUT);
  exit 0;
}

sub run {
  my $self = shift;

  print "eg version $VERSION\n" if $DEBUG < 2;
  print "    >>(We can print the eg version directly)<<\n" if $DEBUG == 2;
  return $self->SUPER::run();
}



#*************************************************************************#
#*************************************************************************#
#*************************************************************************#
#                             UTILITY CLASSES                             #
#*************************************************************************#
#*************************************************************************#
#*************************************************************************#

###########################################################################
# ExecUtil                                                                #
###########################################################################
package ExecUtil;

# _execute_impl is the guts for execute() and execute_captured()
sub _execute_impl ($@) {
  my ($command, @opts) = @_;
  my ($ret, $output);
  my %options = ( ignore_ret => 0, capture_output => 0, @opts );

  if ($DEBUG) {
    print "    >>Running: '$command'<<\n";
    return $options{capture_output} ? (0, "") : 0 if $DEBUG == 2;
  }

  #
  # Execute the relevant command, in a subdirectory if needed, and capturing
  # stdout and stderr if wanted
  #
  if ($options{capture_output}) {
    if ($options{capture_stdout_only}) {
      $output = `$command`;
    } else {
      $output = `$command 2>&1`;
    }
    $ret = $?;
  } elsif (defined $OUTFH) {
    open(OUTPUT, "$command 2>&1 |");
    while (<OUTPUT>) {
      print $OUTFH $_;
    }
    close(OUTPUT);
    $ret = $?;
  } else {
    system($command);
    $ret = $?;
  }

  #
  # Determine retval
  #
  if ($ret != 0) {
    if (($? & 127) == 2) {
      print STDERR "eg: interrupted\n";
    }
    elsif ($? & 127) {
      print STDERR "eg: received signal ".($? & 127)."\n";
    }
    else {
      $ret = ($ret >> 8);
      if (! $options{ignore_ret}) {
        print STDERR "eg: failed ($ret)\n" if $DEBUG;
        if ($ret >> 8 != 0) {
          print STDERR "eg: command ($command) failed\n";
        }
        elsif ($ret != 0) {
          print STDERR "eg: command ($command) died (retval=$ret)\n";
        }
      }
    }
  }

  return $options{capture_output} ? ($ret, $output) : $ret;
}

# executes a command, capturing its output (both STDOUT and STDERR),
# returning both the return value and the output
sub execute_captured ($@) {
  my ($command, @options) = @_;
  return _execute_impl($command, capture_output => 1, @options);
}

# executes a command, returning its chomped output
sub output ($@) {
  my ($command, @options) = @_;
  my ($ret, $output) = execute_captured($command, @options);
  die "Failed executing '$command'!\n" if $ret != 0;
  chomp($output);
  return $output
}

# executes a command (output not captured), returning its return value
sub execute ($@) {
  my ($command, @options) = @_;
  return _execute_impl($command, @options);
}

###########################################################################
# RepoUtil                                                                #
###########################################################################
package RepoUtil;

# current_branch: Get the currently active branch
sub current_branch () {
  Util::push_debug(new_value => $DEBUG ? 1 : 0);
  my ($ret, $output) = ExecUtil::execute_captured("$GIT_CMD symbolic-ref HEAD",
                                                  ignore_ret => 1);
  Util::pop_debug();

  return undef if $ret != 0;
  chomp($output);
  $output =~ s#refs/heads/## || die "Current branch ($output) is funky.\n";
  return $output;
}

sub git_dir (%) {
  my $options = {force => 0, @_};  # Hashref initialized as we're told
  if (!$options->{force}) {
    return $GITDIR if ($GITDIR);
  }

  Util::push_debug(new_value => 0);
  my ($ret, $output) = 
    ExecUtil::execute_captured("$GIT_CMD rev-parse --git-dir", ignore_ret => 1);
  Util::pop_debug();

  return undef if $ret != 0;
  chomp($output);
  return $output;
}

sub get_dirs () {
  my $options = {force => 0, @_};  # Hashref initialized as we're told

  if ($CURDIR && !$options->{force}) {
    return ($CURDIR, $TOPDIR, $GITDIR);
  }

  Util::push_debug(new_value => 0);

  $CURDIR = main::getcwd();

  # Get the toplevel repository directory
  $TOPDIR = $CURDIR;
  my ($ret, $rel_dir) = 
    ExecUtil::execute_captured("$GIT_CMD rev-parse --show-prefix",
                               ignore_ret => 1);
  chomp($rel_dir);
  if ($ret != 0) {
    $TOPDIR = undef;
  } elsif ($rel_dir) {
    $rel_dir =~ s#/$##;  # Remove trailing slash
    $TOPDIR =~ s#\Q$rel_dir\E$##;
    $TOPDIR =~ s#/$##;  # Remove trailing slash
  }

  $GITDIR = git_dir(force => $options->{force});

  Util::pop_debug();

  return ($CURDIR, $TOPDIR, $GITDIR);
}

sub initial_commit () {
  my @output = `$GIT_CMD rev-parse --verify -q HEAD`;
  return $?;
}

sub valid_ref ($) {
  my ($ref) = @_;
  my ($ret, $sha1sum) =
    ExecUtil::execute_captured("$GIT_CMD rev-parse --verify -q $ref",
                               ignore_ret => 1);
  return $ret == 0;
}

sub files_modified () {
  my @output = `$GIT_CMD status -a`;
  return $? == 0;
}

sub merge_branches () {
  my $git_dir = RepoUtil::git_dir();
  my $active_branch = RepoUtil::current_branch() || 'HEAD';
  my @merge_branches =
    `cat "$git_dir/MERGE_HEAD" | $GIT_CMD name-rev --stdin`;
  @merge_branches = map { /^[0-9a-f]* \((.*)\)$/ && $1 } @merge_branches;
  my @all_merge_branches = ($active_branch, @merge_branches);
  return @all_merge_branches;
}

sub get_special_state ($) {
  my $git_dir = shift;

  my $special_state;
  if ( -d "$git_dir/rebase-apply" ) {
    if ( -f "$git_dir/rebase-apply/rebasing" ) {
      return "REBASE";
    } elsif ( -f "$git_dir/rebase-apply/applying" ) {
      return "APPLY MAIL";
    } else {
      return "APPLY MAIL OR REBASE";
    }
  } elsif ( -f "$git_dir/rebase-merge/interactive" ) {
    return "INTERACTIVE REBASE";
  } elsif ( -d "$git_dir/rebase-merge" ) {
    return "MERGE REBASE";
  } elsif ( -f "$git_dir/MERGE_HEAD" ) {
    return "MERGE";
  } elsif ( -f "$git_dir/BISECT_LOG" ) {
    return "BISECT";
  }
  return $special_state;
}

sub get_config ($) {
  my $key = shift;
  my ($ret, $output) = ExecUtil::execute_captured("$GIT_CMD config --get $key",
                                                  ignore_ret => 1);
  return undef if $ret != 0;
  chomp($output);
  return $output;
}

sub set_config ($$) {
  my $key = shift;
  my $value = shift;
  ExecUtil::execute("$GIT_CMD config $key \"$value\"");
}

# XXX unused?
sub unset_config ($) {
  my $key = shift;
  ExecUtil::execute("$GIT_CMD config --unset $key", ignore_ret => 1);
}

sub get_only_branch ($$) {
  my $repository = shift;
  my $check_type = shift;

  if ($DEBUG == 2) {
    print "    >>Running: '$GIT_CMD ls-remote -h $repository'<<\n";
    return;
  }

  # Check if the remote repository has exactly 1 branch...if so, return it,
  # otherwise throw an error
  my ($quoted_repo) = Util::quote_args("$repository");
  my ($ret, $output) =
    ExecUtil::execute_captured("$GIT_CMD ls-remote -h $quoted_repo",
                               capture_stdout_only => 1, ignore_ret => 1);
  die "Aborting: Could not determine remote branches " .
      "from repository '$repository'\n" if $ret != 0;
  my @remote_refs = split('\n', $output);

  die "'$repository' has no branches to $check_type!\n" if @remote_refs == 0;
  my @remote_branches = map { m#[0-9a-f]+.*/(.*)$# && $1 } @remote_refs;

  if (@remote_branches > 1) {
    if ($check_type && $check_type eq "push") {
      print STDERR <<EOF;
Aborting: It is not clear which remote branch to push changes to.  Please
retry, specifying which branch(es) you want to push into from your current
EOF
    } else {
    print STDERR <<EOF;
Aborting: It is not clear which remote branch to pull changes from.  Please
retry, specifying which branch(es) you want to be merged into your current
EOF
    }
    print STDERR <<EOF;
branch.  Existing remote branches of
  $repository
are
  @remote_branches
EOF
    exit 1;
  }

  return $remote_branches[0];
}

sub get_default_push_pull_repository () {
  my $branch = current_branch();

  if ($branch) {
    my $default_remote = `$GIT_CMD config --get branch.$branch.remote`;
    if ($default_remote) {
      chomp($default_remote);
      return $default_remote;
    }
  }

  my @output = `$GIT_CMD config --get-regexp remote\.origin\.*`;
  if (@output) {
    return "origin";
  } else {
    print STDERR <<EOF;
Aborting: No repository specified, and "origin" is not set up as a remote
repository.  Please specify a repository or setup "origin" by running
  eg remote add origin URL
EOF
    exit 1;
  }
}

sub print_new_unknowns ($) {
  my ($new_unknowns) = @_;
  my $num = scalar(@$new_unknowns);
  print STDERR "New unknown files";
  print STDERR " include" if $num > 5;
  print STDERR ":\n";
  my $i = 0;
  foreach my $file (@$new_unknowns) {
    print STDERR "  $file\n";
    last if (++$i >= 5);
  }
  if ($num > 5) {
    print STDERR "Run 'eg status' to see a full list of new unknown files.\n";
  }
  exit 1;
}

# Error messages spewed by commit with non-clean working copies
sub commit_error_message_checks ($$$$) {
  my ($commit_type, $check_for, $status, $new_unknown) = @_;

  if ($check_for->{unmerged_changes} && $status->{has_unmerged_changes}) {
    print STDERR <<EOF;
Aborting: You have unresolved conflicts from your merge (run 'eg status' to get
the list of files with conflicts).  You must first resolve any conflicts and
then mark the relevant files as being ready for commit (see 'eg help stage' to
learn how to do so) before proceeding.
EOF
    exit 1;
  }

  if ($check_for->{no_changes} && $status->{has_no_changes}) {
    # There doesn't need to be any changes for a commit if we're trying to
    # make a merge commit.
    my $gitdir = git_dir();
    if ( ! -f "$gitdir/MERGE_HEAD" ) {
      die "Aborting: Nothing to commit (run 'eg status' for details).\n";
    }
  }
  elsif ($check_for->{unknown} && $check_for->{partially_staged} &&
         $status->{has_new_unknown_files} && 
         $status->{has_unstaged_changes} && $status->{has_staged_changes}) {
    print STDERR <<EOF;
Aborting: It is not clear which changes should be committed; you have new
unknown files, staged (explictly marked as ready for commit) changes, and
unstaged changes all present.  Run 'eg help $commit_type' for details (in
particular, the -b option and either the -a or --staged options).
EOF
    print_new_unknowns($new_unknown);
  }
  elsif ($check_for->{unknown} && $status->{has_new_unknown_files}) {
    print STDERR <<EOF;
Aborting: You have new unknown files present and it is not clear whether
they should be committed.  Run 'eg help $commit_type' for details (in
particular the -b option).
EOF
    print_new_unknowns($new_unknown);
  }
  elsif ($check_for->{partially_staged} &&
         $status->{has_unstaged_changes} && $status->{has_staged_changes}) {
    print STDERR <<EOF;
Aborting: It is not clear which changes should be committed; you have both
staged (explictly marked as ready for commit) changes and unstaged changes
present.  Run 'eg help $commit_type' for details (in particular, the -a and
--staged options).
EOF
    exit 1;
  }
}

# Error messages spewed by push, publish for non-clean working copies
sub push_error_message_checks ($$$$) {
  my ($clean_check_type, $check_for, $status, $new_unknown) = @_;

  if ($check_for->{unmerged_changes} && $status->{has_unmerged_changes}) {
    print STDERR <<EOF;
Aborting: You have unresolved conflicts from your merge (run 'eg status' to get
the list of files with conflicts).  You should first resolve any conflicts
before trying to $clean_check_type your work elsewhere.
EOF
    exit 1;
  }

  if ($check_for->{unknown} && $check_for->{changes} &&
      $status->{has_new_unknown_files} && 
      ($status->{has_unstaged_changes} || $status->{has_staged_changes})) {
    print STDERR <<EOF;
Aborting: You have new unknown files and changed files present.  You should
first commit any such changes (and/or use the -b flag to bypass this check)
before trying to $clean_check_type your work elsewhere.
EOF
    print_new_unknowns($new_unknown);
  }
  elsif ($check_for->{unknown} && $status->{has_new_unknown_files}) {
    print STDERR <<EOF;
Aborting: You have new unknown files present.  You should either commit these
new files before trying to $clean_check_type your work elsewhere, or use the
-b flag to bypass this check.
EOF
    print_new_unknowns($new_unknown);
  }
  elsif ($check_for->{changes} &&
         ($status->{has_unstaged_changes} || $status->{has_staged_changes})) {
    print STDERR <<EOF;
Aborting: You have modified your files since the last commit. You should
first commit any such changes before trying to $clean_check_type your work
elsewhere, or use the -b flag to bypass this check.
EOF
    exit 1;
  }
}

# XXX called with 0 args or 2 args
sub commit_push_checks (;$$) {
  my $clean_check_type = shift;
  my $check_for = shift || {};
  my %status;

  # Determine some useful directories
  my ($cur_dir, $top_dir, $git_dir) = RepoUtil::get_dirs();

  # Save debug mode, print out commands used up front
  if ($DEBUG) {
    Util::push_debug(new_value => 0);
    if ($clean_check_type) {
      print "    >>Commands to gather data for pre-$clean_check_type sanity checks:\n";
    } else {
      print "    >>Commands to gather data for sanity checks:\n";
    }
    print "        $GIT_CMD status\n";
    print "        $GIT_CMD ls-files --unmerged\n";
    print "        $GIT_CMD symbolic-ref HEAD\n" if $check_for->{no_branch};
    print "        cd $top_dir && $GIT_CMD ls-files --exclude-standard --others --directory --no-empty-directory\n";
  } else {
    Util::push_debug(new_value => 0);
  }

  # Determine which types of changes are present
  my ($ret, $output) = ExecUtil::execute_captured("$EG_EXEC status",
                                                  ignore_ret => 1);
  my @unmerged_files = `$GIT_CMD ls-files --unmerged`;
  $status{has_new_unknown_files} = ($output =~ /^Newly created unknown files:$/m);
  $status{has_unstaged_changes}  = ($output =~ /^Changed but not updated/m);
  $status{has_staged_changes}    = ($output =~ /^Changes ready to be commit/m);
  $status{has_unmerged_changes}  = (scalar @unmerged_files > 0);
  $status{has_no_changes}        = !$status{has_unstaged_changes} &&
                                   !$status{has_staged_changes} &&
                                   !$status{has_unmerged_changes};
  $status{output} = $output;

  # Determine which unknown files are "newly created"
  my @new_unknown = `(cd "$top_dir" && $GIT_CMD ls-files --exclude-standard --others --directory --no-empty-directory)`;
  chomp(@new_unknown);
  if ($check_for->{unknown} && $status{has_new_unknown_files} &&
      -f "$git_dir/info/ignored-unknown") {
    my @old_unknown_files = `cat "$git_dir/info/ignored-unknown"`;
    chomp(@old_unknown_files);
    @new_unknown = Util::difference(\@new_unknown, \@old_unknown_files);
    $status{has_new_unknown_files} = (scalar(@new_unknown) > 0);
  }
  @new_unknown =
    Util::reroot_paths__from_to_files($top_dir, $cur_dir, @new_unknown);

  Util::pop_debug();

  if ($check_for->{no_branch}) {
    my $rc = system('$GIT_CMD symbolic-ref -q HEAD >/dev/null');
    $status{has_no_branch} = $rc >> 8;
  }

  return \%status if !defined $clean_check_type;

  if ($clean_check_type =~ /commit/) {
    commit_error_message_checks($clean_check_type,
                                $check_for,
                                \%status,
                                \@new_unknown);
  } elsif ($clean_check_type eq "push" || $clean_check_type eq "publish") {
    push_error_message_checks($clean_check_type,
                              $check_for,
                              \%status,
                              \@new_unknown);
  } else {
    die "Unrecognized clean_check_type: $clean_check_type";
  }

  return \%status;
}

sub record_ignored_unknowns () {
  # Determine some useful directories
  my ($cur_dir, $top_dir, $git_dir) = RepoUtil::get_dirs();

  mkdir "$git_dir/info" unless -d "$git_dir/info";
  open(OUTPUT, "> $git_dir/info/ignored-unknown");
  my @unknown_files = `cd "$top_dir" && $GIT_CMD ls-files --exclude-standard --others --directory --no-empty-directory`;
  foreach my $file (@unknown_files) {
    print OUTPUT $file;
  }
  close(OUTPUT);
}

sub parse_args ($@) {
  my $multi_args = shift;
  my (@args) = @_;

  Util::push_debug(new_value => 0);

  my (@opts, @revs, @files);
  my $stop_marker_found;

  # Get the opts
  while (@args) {
    my $arg = shift @args;
    if ($arg eq "--") {
      $stop_marker_found = 1;
      last;
    }

    if ($arg =~ /^-/) {
      push(@opts, $arg);
      push(@opts, shift @args) if (grep {$arg eq $_} @$multi_args);
    } else {
      unshift(@args, $arg);
      last;
    }
  }

  # Get the revisions
  if (!$stop_marker_found) {
    while (@args) {
      my $arg = shift @args;
      if ($arg eq "--") {
        $stop_marker_found = 1;
        last;
      }

      my @revs_to_check = split('\.\.\.?', $arg);
      my $found_invalid_ref = 0;
      foreach my $ref (@revs_to_check) {
        if (!RepoUtil::valid_ref($ref)) {
          $found_invalid_ref = 1;
          last;
        }
      }
      if ($found_invalid_ref) {
        unshift(@args, $arg);
        last;
      } else {
        push(@revs, $arg);
      }
    }
  }

  # Get the files
  @files = @args;
  if (!$stop_marker_found && @files && $files[0] eq "--") {
    shift @files;
  } else {
    # If "--" appears in argument list and not at front, then some bad
    # revisions specified by the user showed up in our @files list since
    # they didn't validate as existing revisions.
    my $i = -1;
    foreach my $file (@files) {
      if ($file eq "--") {
        die "Bad revision(s): @files[0..$i]\n";
      }
      ++$i;
    }
  }

  ## FIXME: I should add sanity checking: whether there are too many revs
  ## specified (or too few), whether any of @revs are also valid filenames,
  ## and maybe whether all @files refer to valid paths (maybe including
  ## only allowing files instead of also directories)

  Util::pop_debug();

  return (\@opts, \@revs, \@files);
}

sub get_revert_info ($@) {
  my ($revision, @quoted_files) = @_;

  my $marker = "";
  $marker = "--" if (@quoted_files);

  my @newly_added_files;
  my @new_since_rev_files;
  my @other_files = @quoted_files;

  # If this is a merge commit...
  my ($cur_dir, $top_dir, $git_dir) = RepoUtil::get_dirs();
  my @merge_branches;
  if (-f "$git_dir/MERGE_HEAD") {
    @merge_branches = `cat "$git_dir/MERGE_HEAD"`;
    chomp(@merge_branches);
  }

  # Define how to get newly added files since a commit, or new files added
  # between two commits
  my $get_newish_files = sub {
    my $ref1 = shift;
    my $ref2 = shift;
    my (@files, @lines);
    if (defined $ref2) {
      @lines = `$GIT_CMD diff-tree -r $ref1 $ref2 $marker @quoted_files`;
    } else {
      @lines = `$GIT_CMD diff-index --cached $ref1 $marker @quoted_files`;
    }
    foreach my $line (@lines) {
      # Check for newly added files (not previously tracked but now staged)
      if ($line =~ /:000000 [0-9]+ 0{40} [0-9a-f]{40} A\t(.*)/) {
        push(@files, $1);
      }
    }

    # git diff-tree and diff-index return files relative to $top_dir, but
    # we want filenames relative to $cur_dir
    if ($top_dir ne $cur_dir) {
      return Util::reroot_paths__from_to_files($top_dir, $cur_dir, @files);
    } else {
      return @files;
    }
  };

  # Now, get the files added to the index since the "last commit"
  @newly_added_files = $get_newish_files->('HEAD');
  for my $branch (@merge_branches) {
    my @files = $get_newish_files->($branch);
    @newly_added_files = Util::intersect(\@newly_added_files, \@files);
  }
  if (@newly_added_files) {
    @newly_added_files = Util::quote_args(@newly_added_files);
    @other_files = Util::difference(\@quoted_files, \@newly_added_files);
  }

  # Now, get the files that exist in the "last commit" but not the specified
  # revision.
  if ($revision ne "HEAD" || @merge_branches) {
    my @branches;
    push(@branches, "HEAD");
    push(@branches, @merge_branches);
    foreach my $branch (@branches) {
      my @files = $get_newish_files->($revision, $branch);
      @new_since_rev_files = Util::union(\@new_since_rev_files, \@files);
    }
    if (@new_since_rev_files) {
      @new_since_rev_files = Util::quote_args(@new_since_rev_files);
      @other_files = Util::difference(\@other_files, \@new_since_rev_files);
    }
  }

  return (\@newly_added_files, \@new_since_rev_files, \@other_files);
}

###########################################################################
# Util                                                                    #
###########################################################################
package Util;

# Return items in @$lista but not in @$listb
sub difference ($$) {
  my ($lista, $listb) = @_;
  my %count;

  foreach my $item (@$lista) { $count{$item}++ };
  foreach my $item (@$listb) { $count{$item}-- };

  my @ret = grep { $count{$_} == 1 } keys %count;
}

# Return items in both @$lista and in @$listb
sub intersect ($$) {
  my ($lista, $listb) = @_;
  my %original;
  my @both = ();

  map { $original{$_} = 1 } @$lista;
  @both = grep { $original{$_} } @$listb;

  return @both;
}

# Return items in either @$lista or @$listb
sub union ($$) {
  my ($lista, $listb) = @_;
  my %either;

  map { $either{$_} = 1 } @$lista;
  map { $either{$_} = 1 } @$listb;

  return keys %either;
}

# Returns whether @$list contains $item
sub contains ($$) {
  my ($list, $item) = @_;
  my $found = 0;
  foreach my $elem (@$list) {
    if ($item eq $elem) {
      $found = 1;
      last;
    }
  }

  return $found;
}

sub uniquify_list (@) {
  my @list = @_;
  my %unique;
  @unique{@list} = @list;
  return keys %unique;
}

sub split_ssh_repository ($) {
  my ($repository) = @_;
  my ($user, $machine, $port, $path);
  if ($repository =~ m#^ssh://((?:.*?@)?)([^/:]*)(?::(\d+))?(.*)$#) {
    $user = $1;
    $machine = $2;
    $port = defined $3 ? "-p $3" : "";
    $path = $4;
    $path =~ s#^/~#~#;  # Change leading /~ into plain ~
  } elsif ($repository =~ m#^((?:.*?@)?)([^:]*):(.*)$#) {
    $user = $1;
    $machine = $2;
    $port = "";
    $path = $3;
  }
  return ($user, $machine, $port, $path);
}

sub quote_args (@) {
  my @args = @_;

  # Quote arguments with special characters so that when we
  # do something like
  #   system("$command hardcoded_arg1 @args")
  # that the @args will get passed correctly to the shell command $command
  my @newargs;
  foreach my $arg (@args) {
    my $quotes_needed = 0;
    if (!$arg || $arg =~ /[;'"<>()\[\]|`* 	\n\$\\~]/) {
      $quotes_needed = 1;
    }

    $arg =~ s#\\#\\\\#g;    # Backslash escape backslashes
    $arg =~ s#"#\\"#g;      # Backslash escape quotes
    $arg =~ s#`#\\`#g;      # Backslash escape backticks
    $arg =~ s#\$#\\\$#g;    # Backslash escape dollar signs

    $arg = '"'.$arg.'"' if $quotes_needed;

    push(@newargs, $arg);
  }
  return @newargs;
}

# Have git's rev-parse command parse @args and decide which part is files,
# which is options, and which are revisions.  Further, have git translate
# revisions into full 40-character hexadecimal commit ids.
sub git_rev_parse (@) {
  my @args = @_;

  Util::push_debug(new_value => 0);

  my @quoted_args = Util::quote_args(@args);
  my ($ret, $output) = 
    ExecUtil::execute_captured("$GIT_CMD rev-parse @quoted_args",
                               ignore_ret => 1);
  if ($ret != 0) {
    $output =~ /^(fatal:.*)$/m   && print STDERR "$1\n";
    $output =~ /^(Use '--'.*)$/m && print STDERR "$1\n";
    exit 1;
  }
  my @opts  =
    split('\n', `$GIT_CMD rev-parse --no-revs --flags    @quoted_args`);
  my @revs  =
    split('\n', `$GIT_CMD rev-parse --revs-only          @quoted_args`);
  my @files =
    split('\n', `$GIT_CMD rev-parse --no-revs --no-flags @quoted_args`);

  # Translate sha1sums back to human specified version of revisions.  Note that
  # something like "REV1...REV2" is translated into "SHA1 SHA2 ^SHA3", so one
  # argument may have become 3 revisions.  options and files should translate
  # one to one, though, so we can back out the original revision names.
  @revs = @args[scalar(@opts)..scalar(@args)-scalar(@files)-1];

  Util::pop_debug();

  return (\@opts, \@revs, \@files);
}

# reroot_paths__from_to_files
#   Given
#     $from   absolute path of directory files were originally relative to
#     $to     absolute path of directory you want files relative to
#     @files  list of files with paths relative to $from
#   returns a list of files with paths relative to $to
#   For example:
#     reroot_paths__from_to_files("/home", "/home/newren", ('bar', '../foo'))
#   would return
#     ('../bar', '../../foo')
#   Another example:
#     reroot_paths__from_to_files("/tmp/junk", "/tmp", ('bar', '../foo'))
#   would return
#     ('junk/bar', 'foo')
sub reroot_paths__from_to_files ($$@) {
  my ($from, $to, @files) = @_;
  $from =~ s#/*$#/#;   # Make sure $from ends with exactly 1 slash
  $to   =~ s#/*$#/#;   # Make sure $to   ends with exactly 1 slash

  my @new_paths;
  foreach my $file (@files) {
    # Get the old path for the file, removing any "PATH/.." sequences
    my $oldpath = "$from$file";
    $oldpath =~ s#/+#/#;               # Remove duplicate slashes in path
    $oldpath = "$1$2" while $oldpath =~ m#^(.*?)(?!\.\./)[^/]+/\.\./(.*)$#;

    # Find what $oldpath and $to have in common
    my $common_leading_path = "";
    my $combined = "$oldpath\n$to";
    if ($combined =~ m#^(.*/).*\n\1.*$#) {
      $common_leading_path = $1;
    }

    # Now get the unique parts of $oldpath and $to
    my $remainder_old_path = substr($oldpath, length($common_leading_path));
    my $remainder_to       = substr($to,      length($common_leading_path));

    # Do an s/DIRECTORY_NAME/../ on remainder_to, since we want to know
    # the relative path for getting from $to to $from.
    $remainder_to =~ s#[^/]+#..#g;

    push(@new_paths, "$remainder_to$remainder_old_path");
  }

  return @new_paths;
}

{
my @debug_values;
sub push_debug (@) {
  my @opts = @_;
  my %options = ( @opts );
  die "Called without new_value!" if !defined($options{new_value});

  my $old_value = $DEBUG;
  push(@debug_values, $DEBUG);
  $DEBUG = $options{new_value};
  return $old_value;
}

sub pop_debug () {
  $DEBUG = pop @debug_values;
}
}


#*************************************************************************#
#*************************************************************************#
#*************************************************************************#
#                              MAIN PROGRAM                               #
#*************************************************************************#
#*************************************************************************#
#*************************************************************************#

package main;

sub launch ($) {
  my $job=shift;
  $job = $ALIAS{$job} || $job;
  my $orig_job = $job;
  $job =~ s/-/_/;  # Packages must have underscores, commands often have dashes

  # Create the action to execute
  my $action;
  $action = $job->new()                           if  $job->can("new");
  $action = subcommand->new(command => $orig_job) if !$job->can("new");
  my $ret;

  # preprocess
  if ($action->can("preprocess")) {
    # Do not skip commands normally executed during the preprocess stage,
    # since they just gather data.
    Util::push_debug(new_value => $DEBUG ? 1 : 0);

    print ">>Stage: Preprocess<<\n" if $DEBUG;
    $action->preprocess();

    Util::pop_debug();
  }

  # run & postprocess
  if (!$action->can("postprocess")) {
    print ">>Stage: Run<<\n" if $DEBUG;
    $ret = $action->run();
  } else {
    my $output = "";
    open($OUTFH, '>', \$output) || die "eg $job: cannot open \$OUTFH: $!";
    print ">>Stage: Run<<\n" if $DEBUG;
    $ret = $action->run();
    print ">>Stage: Postprocess<<\n" if $DEBUG;
    $action->postprocess($output);
  }

  # wrapup
  if ($action->can("wrapup")) {
    print ">>Stage: Wrapup<<\n" if $DEBUG;
    $action->wrapup();
  }

  $ret = 0 unless ($ret);
  exit $ret;
}

sub version () {
  my $version_obj = "version"->new();
  $version_obj->run();
  exit 0;
}

# User gave invalid input; print an error_message, then show command usage
sub help (;$) {
  my $error_message = shift;
  my %extra_args;

  # Clear out any arguments so that help object doesn't think we asked for
  # a specific help topic.
  @ARGV = ();

  # Print any error message we were given
  if (defined $error_message) {
    print STDERR "$error_message\n\n";
    $extra_args{exit_status} = 1;
  }

  # Now show help.
  my $help_obj = "help"->new(%extra_args);
  $help_obj->run();
}

sub main () {
  #
  # Get any global options 
  #
  Getopt::Long::Configure("no_bundling", "no_permute",
                          "pass_through", "no_auto_abbrev", "no_ignore_case");
  my @global_args  = ();
  my $record_arg   = sub { push(@global_args, "--$_[0]"); };
  my $record_args  = sub { push(@global_args, "--$_[0]=$_[1]"); };
  my $result=GetOptions(
               "--debug"     => sub { $DEBUG = 1 },
               "--help"      => sub { help()     },
               "--translate" => sub { $DEBUG = 2 },
               "--version"   => sub { version()  },
               "exec-path:s" => sub { $_[1] ? &$record_args(@_)
                                            : &$record_arg(@_); },
               "paginate|p"  => sub { $USE_PAGER = 1; &$record_arg(@_)  },
               "no-pager"    => sub { $USE_PAGER = 0; &$record_arg(@_)  },
               "bare"        => sub { &$record_arg(@_)  },
               "git-dir=s"   => sub { &$record_args(@_) },
               "work-tree=s" => sub { &$record_args(@_) },
               "no-replace-objects" => sub { &$record_arg(@_) },
                        );
  # Make sure all global args are passed to eg subprocesses as well...
  @global_args = Util::quote_args(@global_args);
  $GIT_CMD .= " @global_args";
  $EG_EXEC .= " @global_args" if @global_args;

  #
  # Fix the environment, if needed (eg testsuite invokes eg via 'git', but
  # eg needs to be able to call the real git).
  # WARNING: This does not handle mutual recursion (eg in PATH twice as 'git')
  #
  if ($0 =~ m#(.*)/git$#) {
    my $baddir = $1;
    my @newpaths = grep {$_ ne $baddir} split(/:/, $ENV{PATH});
    $ENV{PATH} = join(':', @newpaths);
  }

  # Sanity check the arguments
  exit ExecUtil::execute($GIT_CMD) if $GIT_CMD =~ m#--exec-path$#;
  die "eg: Error parsing arguments. (Try 'eg help')\n" if !$result;
  die "eg: No subcommand specified. (Try 'eg help')\n" if @ARGV < 1;
  die "eg: Invalid argument '$ARGV[0]'. (Try 'eg help')\n"
    if ($ARGV[0] !~ m#^[a-z]#);

  #
  # Now execute the action
  #
  my $action = shift @ARGV;
  launch($action);
}

main();
