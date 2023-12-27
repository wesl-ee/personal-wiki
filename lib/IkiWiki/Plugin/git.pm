#!/usr/bin/perl
package IkiWiki::Plugin::git;

use warnings;
use strict;
use IkiWiki;
use Encode;
use File::Path qw{remove_tree};
use URI::Escape q{uri_escape_utf8};
use open qw{:utf8 :std};

my $sha1_pattern     = qr/[0-9a-fA-F]{40}/; # pattern to validate Git sha1sums
my $dummy_commit_msg = 'dummy commit';      # message to skip in recent changes

sub import {
	hook(type => "checkconfig", id => "git", call => \&checkconfig);
	hook(type => "getsetup", id => "git", call => \&getsetup);
	hook(type => "genwrapper", id => "git", call => \&genwrapper);
	hook(type => "rcs", id => "rcs_update", call => \&rcs_update);
	hook(type => "rcs", id => "rcs_prepedit", call => \&rcs_prepedit);
	hook(type => "rcs", id => "rcs_commit", call => \&rcs_commit);
	hook(type => "rcs", id => "rcs_commit_staged", call => \&rcs_commit_staged);
	hook(type => "rcs", id => "rcs_add", call => \&rcs_add);
	hook(type => "rcs", id => "rcs_remove", call => \&rcs_remove);
	hook(type => "rcs", id => "rcs_rename", call => \&rcs_rename);
	hook(type => "rcs", id => "rcs_recentchanges", call => \&rcs_recentchanges);
	hook(type => "rcs", id => "rcs_diff", call => \&rcs_diff);
	hook(type => "rcs", id => "rcs_getctime", call => \&rcs_getctime);
	hook(type => "rcs", id => "rcs_getmtime", call => \&rcs_getmtime);
	hook(type => "rcs", id => "rcs_receive", call => \&rcs_receive);
	hook(type => "rcs", id => "rcs_preprevert", call => \&rcs_preprevert);
	hook(type => "rcs", id => "rcs_revert", call => \&rcs_revert);
	hook(type => "rcs", id => "rcs_find_changes", call => \&rcs_find_changes);
	hook(type => "rcs", id => "rcs_get_current_rev", call => \&rcs_get_current_rev);
}

sub checkconfig () {
	if (! defined $config{gitorigin_branch}) {
		$config{gitorigin_branch}="origin";
	}
	if (! defined $config{gitmaster_branch}) {
		$config{gitmaster_branch}="master";
	}
	if (defined $config{git_wrapper} &&
	    length $config{git_wrapper}) {
		push @{$config{wrappers}}, {
			wrapper => $config{git_wrapper},
			wrappermode => (defined $config{git_wrappermode} ? $config{git_wrappermode} : "06755"),
			wrapper_background_command => $config{git_wrapper_background_command},
		};
	}

	if (defined $config{git_test_receive_wrapper} &&
	    length $config{git_test_receive_wrapper} &&
	    defined $config{untrusted_committers} &&
	    @{$config{untrusted_committers}}) {
		push @{$config{wrappers}}, {
			test_receive => 1,
			wrapper => $config{git_test_receive_wrapper},
			wrappermode => (defined $config{git_wrappermode} ? $config{git_wrappermode} : "06755"),
		};
	}

	# Avoid notes, parser does not handle and they only slow things down.
	$ENV{GIT_NOTES_REF}="";
	
	# Run receive test only if being called by the wrapper, and not
	# when generating same.
	if ($config{test_receive} && ! exists $config{wrapper}) {
		require IkiWiki::Receive;
		IkiWiki::Receive::test();
	}
}

sub getsetup () {
	return
		plugin => {
			safe => 0, # rcs plugin
			rebuild => undef,
			section => "rcs",
		},
		git_wrapper => {
			type => "string",
			example => "/git/wiki.git/hooks/post-update",
			description => "git hook to generate",
			safe => 0, # file
			rebuild => 0,
		},
		git_wrapper_background_command => {
			type => "string",
			example => "git push github",
			description => "shell command for git_wrapper to run, in the background",
			safe => 0, # command
			rebuild => 0,
		},
		git_wrappermode => {
			type => "string",
			example => '06755',
			description => "mode for git_wrapper (can safely be made suid)",
			safe => 0,
			rebuild => 0,
		},
		git_test_receive_wrapper => {
			type => "string",
			example => "/git/wiki.git/hooks/pre-receive",
			description => "git pre-receive hook to generate",
			safe => 0, # file
			rebuild => 0,
		},
		untrusted_committers => {
			type => "string",
			example => [],
			description => "unix users whose commits should be checked by the pre-receive hook",
			safe => 0,
			rebuild => 0,
		},
		historyurl => {
			type => "string",
			example => "http://git.example.com/gitweb.cgi?p=wiki.git;a=history;f=[[file]];hb=HEAD",
			description => "gitweb url to show file history ([[file]] substituted)",
			safe => 1,
			rebuild => 1,
		},
		diffurl => {
			type => "string",
			example => "http://git.example.com/gitweb.cgi?p=wiki.git;a=blobdiff;f=[[file]];h=[[sha1_to]];hp=[[sha1_from]];hb=[[sha1_commit]];hpb=[[sha1_parent]]",
			description => "gitweb url to show a diff ([[file]], [[sha1_to]], [[sha1_from]], [[sha1_commit]], and [[sha1_parent]] substituted)",
			safe => 1,
			rebuild => 1,
		},
		gitorigin_branch => {
			type => "string",
			example => "origin",
			description => "where to pull and push changes (set to empty string to disable)",
			safe => 0, # paranoia
			rebuild => 0,
		},
		gitmaster_branch => {
			type => "string",
			example => "master",
			description => "branch that the wiki is stored in",
			safe => 0, # paranoia
			rebuild => 0,
		},
}

sub genwrapper {
	if ($config{test_receive}) {
		require IkiWiki::Receive;
		return IkiWiki::Receive::genwrapper();
	}
	else {
		return "";
	}
}

# Loosely based on git-new-workdir from git contrib.
sub create_temp_working_dir ($$) {
	my $rootdir = shift;
	my $branch = shift;
	my $working = "$rootdir/.git/ikiwiki-temp-working";
	remove_tree($working);

	foreach my $dir ("", ".git") {
		if (!mkdir("$working/$dir")) {
			error("Unable to create $working/$dir: $!");
		}
	}

	# Hooks are deliberately not included: we will commit to the temporary
	# branch that is used in the temporary working tree, and we don't want
	# to run the post-commit hook there.
	#
	# logs/refs is not included because we don't use the reflog.
	# remotes, rr-cache, svn are similarly excluded.
	foreach my $link ("config", "refs", "objects", "info", "packed-refs") {
		if (!symlink("../../$link", "$working/.git/$link")) {
			error("Unable to create symlink $working/.git/$link: $!");
		}
	}

	open (my $out, '>', "$working/.git/HEAD") or
		error("failed to write $working.git/HEAD: $!");
	print $out "ref: refs/heads/$branch\n" or
		error("failed to write $working.git/HEAD: $!");
	close $out or
		error("failed to write $working.git/HEAD: $!");
	return $working;
}

sub safe_git {
	# Start a child process safely without resorting to /bin/sh.
	# Returns command output (in list content) or success state
	# (in scalar context), or runs the specified data handler.

	my %params = @_;

	my $pid = open my $OUT, "-|";

	error("Working directory not specified") unless defined $params{chdir};
	error("Cannot fork: $!") if !defined $pid;

	if (!$pid) {
		# In child.
		# Git commands want to be in wc.
		if ($params{chdir} ne '.') {
			chdir $params{chdir}
			    or error("cannot chdir to $params{chdir}: $!");
		}

		if ($params{stdout}) {
			open(STDOUT, '>&', $params{stdout}) or error("Cannot reopen stdout: $!");
		}

		exec @{$params{cmdline}} or error("Cannot exec '@{$params{cmdline}}': $!");
	}
	# In parent.

	# git output is probably utf-8 encoded, but may contain
	# other encodings or invalidly encoded stuff. So do not rely
	# on the normal utf-8 IO layer, decode it by hand.
	binmode($OUT);

	my @lines;
	while (<$OUT>) {
		$_=decode_utf8($_, 0);

		chomp;

		if (! defined $params{data_handler}) {
			push @lines, $_;
		}
		else {
			last unless $params{data_handler}->($_);
		}
	}

	close $OUT;

	$params{error_handler}->("'@{$params{cmdline}}' failed: $!") if $? && $params{error_handler};

	return wantarray ? @lines : ($? == 0);
}
# Convenient wrappers.
sub run_or_die_in ($$@) {
	my $dir = shift;
	safe_git(chdir => $dir, error_handler => \&error, cmdline => \@_);
}
sub run_or_cry_in ($$@) {
	my $dir = shift;
	safe_git(chdir => $dir, error_handler => sub { warn @_ }, cmdline => \@_);
}
sub run_or_non_in ($$@) {
	my $dir = shift;
	safe_git(chdir => $dir, cmdline => \@_);
}

sub ensure_committer ($) {
	my $dir = shift;

	if (! length $ENV{GIT_AUTHOR_NAME} || ! length $ENV{GIT_COMMITTER_NAME}) {
		my $name = join('', run_or_non_in($dir, "git", "config", "user.name"));
		if (! length $name) {
			run_or_die_in($dir, "git", "config", "user.name", "IkiWiki");
		}
	}

	if (! length $ENV{GIT_AUTHOR_EMAIL} || ! length $ENV{GIT_COMMITTER_EMAIL}) {
		my $email = join('', run_or_non_in($dir, "git", "config", "user.email"));
		if (! length $email) {
			run_or_die_in($dir, "git", "config", "user.email", "ikiwiki.info");
		}
	}
}

sub merge_past ($$$) {
	# Unlike with Subversion, Git cannot make a 'svn merge -rN:M file'.
	# Git merge commands work with the committed changes, except in the
	# implicit case of '-m' of git checkout(1).  So we should invent a
	# kludge here.  In principle, we need to create a throw-away branch
	# in preparing for the merge itself.  Since branches are cheap (and
	# branching is fast), this shouldn't cost high.
	#
	# The main problem is the presence of _uncommitted_ local changes.  One
	# possible approach to get rid of this situation could be that we first
	# make a temporary commit in the master branch and later restore the
	# initial state (this is possible since Git has the ability to undo a
	# commit, i.e. 'git reset --soft HEAD^').  The method can be summarized
	# as follows:
	#
	# 	- create a diff of HEAD:current-sha1
	# 	- dummy commit
	# 	- create a dummy branch and switch to it
	# 	- rewind to past (reset --hard to the current-sha1)
	# 	- apply the diff and commit
	# 	- switch to master and do the merge with the dummy branch
	# 	- make a soft reset (undo the last commit of master)
	#
	# The above method has some drawbacks: (1) it needs a redundant commit
	# just to get rid of local changes, (2) somewhat slow because of the
	# required system forks.  Until someone points a more straight method
	# (which I would be grateful) I have implemented an alternative method.
	# In this approach, we hide all the modified files from Git by renaming
	# them (using the 'rename' builtin) and later restore those files in
	# the throw-away branch (that is, we put the files themselves instead
	# of applying a patch).

	my ($sha1, $file, $message) = @_;

	my @undo;      # undo stack for cleanup in case of an error
	my $conflict;  # file content with conflict markers

	ensure_committer($config{srcdir});

	eval {
		# Hide local changes from Git by renaming the modified file.
		# Relative paths must be converted to absolute for renaming.
		my ($target, $hidden) = (
		    "$config{srcdir}/${file}", "$config{srcdir}/${file}.${sha1}"
		);
		rename($target, $hidden)
		    or error("rename '$target' to '$hidden' failed: $!");
		# Ensure to restore the renamed file on error.
		push @undo, sub {
			return if ! -e "$hidden"; # already renamed
			rename($hidden, $target)
			    or warn "rename '$hidden' to '$target' failed: $!";
		};

		my $branch = "throw_away_${sha1}"; # supposed to be unique

		# Create a throw-away branch and rewind backward.
		push @undo, sub { run_or_cry_in($config{srcdir}, 'git', 'branch', '-D', $branch) };
		run_or_die_in($config{srcdir}, 'git', 'branch', $branch, $sha1);

		# Switch to throw-away branch for the merge operation.
		push @undo, sub {
			if (!run_or_cry_in($config{srcdir}, 'git', 'checkout', $config{gitmaster_branch})) {
				run_or_cry_in($config{srcdir}, 'git', 'checkout','-f',$config{gitmaster_branch});
			}
		};
		run_or_die_in($config{srcdir}, 'git', 'checkout', $branch);

		# Put the modified file in _this_ branch.
		rename($hidden, $target)
		    or error("rename '$hidden' to '$target' failed: $!");

		# _Silently_ commit all modifications in the current branch.
		run_or_non_in($config{srcdir}, 'git', 'commit', '-m', $message, '-a');
		# ... and re-switch to master.
		run_or_die_in($config{srcdir}, 'git', 'checkout', $config{gitmaster_branch});

		# Attempt to merge without complaining.
		if (!run_or_non_in($config{srcdir}, 'git', 'pull', '--no-rebase', '--no-commit', '.', $branch)) {
			$conflict = readfile($target);
			run_or_die_in($config{srcdir}, 'git', 'reset', '--hard');
		}
	};
	my $failure = $@;

	# Process undo stack (in reverse order).  By policy cleanup
	# actions should normally print a warning on failure.
	while (my $handle = pop @undo) {
		$handle->();
	}

	error("Git merge failed!\n$failure\n") if $failure;

	return $conflict;
}

{
my %prefix_cache;

sub decode_git_file ($$) {
	my $dir=shift;
	my $file=shift;

	# git does not output utf-8 filenames, but instead
	# double-quotes them with the utf-8 characters
	# escaped as \nnn\nnn.
	if ($file =~ m/^"(.*)"$/) {
		($file=$1) =~ s/\\([0-7]{1,3})/chr(oct($1))/eg;
	}

	# strip prefix if in a subdir
	if (! defined $prefix_cache{$dir}) {
		($prefix_cache{$dir}) = run_or_die_in($dir, 'git', 'rev-parse', '--show-prefix');
		if (! defined $prefix_cache{$dir}) {
			$prefix_cache{$dir}="";
		}
	}
	$file =~ s/^\Q$prefix_cache{$dir}\E//;

	return decode("utf8", $file);
}
}

sub parse_diff_tree ($$) {
	# Parse the raw diff tree chunk and return the info hash.
	# See git-diff-tree(1) for the syntax.
	my $dir = shift;
	my $dt_ref = shift;

	# End of stream?
	return if ! @{ $dt_ref } ||
		  !defined $dt_ref->[0] || !length $dt_ref->[0];

	my %ci;
	# Header line.
	while (my $line = shift @{ $dt_ref }) {
		return if $line !~ m/^(.+) ($sha1_pattern)/;

		my $sha1 = $2;
		$ci{'sha1'} = $sha1;
		last;
	}

	# Identification lines for the commit.
	while (my $line = shift @{ $dt_ref }) {
		# Regexps are semi-stolen from gitweb.cgi.
		if ($line =~ m/^tree ([0-9a-fA-F]{40})$/) {
			$ci{'tree'} = $1;
		}
		elsif ($line =~ m/^parent ([0-9a-fA-F]{40})$/) {
			# XXX: collecting in reverse order
			push @{ $ci{'parents'} }, $1;
		}
		elsif ($line =~ m/^(author|committer) (.*) ([0-9]+) (.*)$/) {
			my ($who, $name, $epoch, $tz) =
			   ($1,   $2,    $3,     $4 );

			$ci{  $who          } = $name;
			$ci{ "${who}_epoch" } = $epoch;
			$ci{ "${who}_tz"    } = $tz;

			if ($name =~ m/^([^<]+)\s+<([^@>]+)/) {
				$ci{"${who}_name"} = $1;
				$ci{"${who}_username"} = $2;
			}
			elsif ($name =~ m/^([^<]+)\s+<>$/) {
				$ci{"${who}_username"} = $1;
			}
			else {
				$ci{"${who}_username"} = $name;
			}
		}
		elsif ($line =~ m/^$/) {
			# Trailing empty line signals next section.
			last;
		}
	}

	debug("No 'tree' seen in diff-tree output") if !defined $ci{'tree'};
	
	if (defined $ci{'parents'}) {
		$ci{'parent'} = @{ $ci{'parents'} }[0];
	}
	else {
		$ci{'parent'} = 0 x 40;
	}

	# Commit message (optional).
	while ($dt_ref->[0] =~ /^    /) {
		my $line = shift @{ $dt_ref };
		$line =~ s/^    //;
		push @{ $ci{'comment'} }, $line;
	}
	shift @{ $dt_ref } if $dt_ref->[0] =~ /^$/;

	$ci{details} = [parse_changed_files($dir, $dt_ref)];

	return \%ci;
}

sub parse_changed_files ($$) {
	my $dir = shift;
	my $dt_ref = shift;

	my @files;

	# Modified files.
	while (my $line = shift @{ $dt_ref }) {
		if ($line =~ m{^
			(:+)       # number of parents
			([^\t]+)\t # modes, sha1, status
			(.*)       # file names
		$}xo) {
			my $num_parents = length $1;
			my @tmp = split(" ", $2);
			my ($file, $file_to) = split("\t", $3);
			my @mode_from = splice(@tmp, 0, $num_parents);
			my $mode_to = shift(@tmp);
			my @sha1_from = splice(@tmp, 0, $num_parents);
			my $sha1_to = shift(@tmp);
			my $status = shift(@tmp);

			if (length $file) {
				push @files, {
					'file'      => decode_git_file($dir, $file),
					'sha1_from' => $sha1_from[0],
					'sha1_to'   => $sha1_to,
					'mode_from' => $mode_from[0],
					'mode_to'   => $mode_to,
					'status'    => $status,
				};
			}
			next;
		};
		last;
	}

	return @files;
}

sub git_commit_info ($$;$) {
	# Return an array of commit info hashes of num commits
	# starting from the given sha1sum.
	my ($dir, $sha1, $num) = @_;

	my @opts;
	push @opts, "--max-count=$num" if defined $num;

	my @raw_lines = run_or_die_in($dir, 'git', 'log', @opts,
		'--pretty=raw', '--raw', '--abbrev=40', '--always', '-c',
		'-r', $sha1, '--no-renames', '--', '.');

	my @ci;
	while (my $parsed = parse_diff_tree($dir, \@raw_lines)) {
		push @ci, $parsed;
	}

	warn "Cannot parse commit info for '$sha1' commit" if !@ci;

	return wantarray ? @ci : $ci[0];
}

sub rcs_find_changes ($) {
	my $oldrev=shift;

	# Note that git log will sometimes show files being added that
	# don't exist. Particularly, git merge -s ours can result in a
	# merge commit where some files were not really added.
	# This is why the code below verifies that the files really
	# exist.
	my @raw_lines = run_or_die_in($config{srcdir}, 'git', 'log',
		'--pretty=raw', '--raw', '--abbrev=40', '--always', '-c',
		'--no-renames', , '--reverse',
		'-r', "$oldrev..HEAD", '--', '.');

	# Due to --reverse, we see changes in chronological order.
	my %changed;
	my %deleted;
	my $nullsha = 0 x 40;
	my $newrev=$oldrev;
	while (my $ci = parse_diff_tree($config{srcdir}, \@raw_lines)) {
		$newrev=$ci->{sha1};
		foreach my $i (@{$ci->{details}}) {
			my $file=$i->{file};
			if ($i->{sha1_to} eq $nullsha) {
				if (! -e "$config{srcdir}/$file") {
					delete $changed{$file};
					$deleted{$file}=1;
				}
			}
			else {
				if (-e "$config{srcdir}/$file") {
					delete $deleted{$file};
					$changed{$file}=1;
				}
			}
		}
	}

	return (\%changed, \%deleted, $newrev);
}

sub git_sha1_file ($$) {
	my $dir=shift;
	my $file=shift;
	return git_sha1($dir, $file);
}

sub git_sha1 ($@) {
	my $dir = shift;
	# Ignore error since a non-existing file might be given.
	my ($sha1) = run_or_non_in($dir, 'git', 'rev-list', '--max-count=1', 'HEAD',
		'--', @_);
	if (defined $sha1) {
		($sha1) = $sha1 =~ m/($sha1_pattern)/; # sha1 is untainted now
	}
	return defined $sha1 ? $sha1 : '';
}

sub rcs_get_current_rev () {
	return git_sha1($config{srcdir});
}

sub rcs_update () {
	# Update working directory.
	ensure_committer($config{srcdir});

	if (length $config{gitorigin_branch}) {
		run_or_cry_in($config{srcdir}, 'git', 'pull', '--no-rebase', '--prune', $config{gitorigin_branch});
	}
}

sub rcs_prepedit ($) {
	# Return the commit sha1sum of the file when editing begins.
	# This will be later used in rcs_commit if a merge is required.
	my ($file) = @_;

	return git_sha1_file($config{srcdir}, $file);
}

sub rcs_commit (@) {
	# Try to commit the page; returns undef on _success_ and
	# a version of the page with the rcs's conflict markers on
	# failure.
	my %params=@_;

	# Check to see if the page has been changed by someone else since
	# rcs_prepedit was called.
	my $cur = git_sha1_file($config{srcdir}, $params{file});
	my $prev;
	if (defined $params{token}) {
		($prev) = $params{token} =~ /^($sha1_pattern)$/; # untaint
	}

	if (defined $cur && defined $prev && $cur ne $prev) {
		my $conflict = merge_past($prev, $params{file}, $dummy_commit_msg);
		return $conflict if defined $conflict;
	}

	return rcs_commit_helper(@_);
}

sub rcs_commit_staged (@) {
	# Commits all staged changes. Changes can be staged using rcs_add,
	# rcs_remove, and rcs_rename.
	return rcs_commit_helper(@_);
}

sub rcs_commit_helper (@) {
	my %params=@_;
	
	my %env=%ENV;

	if (defined $params{session}) {
		# Set the commit author and email based on web session info.
		my $u;
		if (defined $params{session}->param("name")) {
			$u=$params{session}->param("name");
		}
		elsif (defined $params{session}->remote_addr()) {
			$u=$params{session}->remote_addr();
		}
		if (length $u) {
			$u=encode_utf8(IkiWiki::cloak($u));
			$ENV{GIT_AUTHOR_NAME}=$u;
		}
		else {
			$u = 'anonymous';
		}
		if (defined $params{session}->param("nickname")) {
			$u=encode_utf8($params{session}->param("nickname"));
			$u=~s/\s+/_/g;
			$u=~s/[^-_0-9[:alnum:]]+//g;
		}
		if (length $u) {
			$ENV{GIT_AUTHOR_EMAIL}="$u\@web";
		}
		else {
			$ENV{GIT_AUTHOR_EMAIL}='anonymous@web';
		}
	}

	ensure_committer($config{srcdir});

	$params{message} = IkiWiki::possibly_foolish_untaint($params{message});
	my @opts;
	if ($params{message} !~ /\S/) {
		# Force git to allow empty commit messages.
		# (If this version of git supports it.)
		my ($version)=`git --version` =~ /git version (.*)/;
		if ($version ge "1.7.8") {
			push @opts, "--allow-empty-message", "--no-edit";
		}
		if ($version ge "1.7.2") {
			push @opts, "--allow-empty-message";
		}
		elsif ($version ge "1.5.4") {
			push @opts, '--cleanup=verbatim';
		}
		else {
			$params{message}.=".";
		}
	}
	if (exists $params{file}) {
		push @opts, '--', $params{file};
	}
	# git commit returns non-zero if nothing really changed.
	# So we should ignore its exit status (hence run_or_non_in).
	if (run_or_non_in($config{srcdir}, 'git', 'commit', '-m', $params{message}, '-q', @opts)) {
		if (length $config{gitorigin_branch}) {
			run_or_cry_in($config{srcdir}, 'git', 'push', $config{gitorigin_branch}, $config{gitmaster_branch});
		}
	}
	
	%ENV=%env;
	return undef; # success
}

sub rcs_add ($) {
	# Add file to archive.

	my ($file) = @_;

	ensure_committer($config{srcdir});
	run_or_cry_in($config{srcdir}, 'git', 'add', '--', $file);
}

sub rcs_remove ($) {
	# Remove file from archive.

	my ($file) = @_;

	ensure_committer($config{srcdir});
	run_or_cry_in($config{srcdir}, 'git', 'rm', '-f', '--', $file);
}

sub rcs_rename ($$) {
	my ($src, $dest) = @_;

	ensure_committer($config{srcdir});
	run_or_cry_in($config{srcdir}, 'git', 'mv', '-f', '--', $src, $dest);
}

sub rcs_recentchanges ($) {
	# List of recent changes.

	my ($num) = @_;

	eval q{use Date::Parse};
	error($@) if $@;

	my @rets;
	foreach my $ci (git_commit_info($config{srcdir}, 'HEAD', $num || 1)) {
		# Skip redundant commits.
		next if ($ci->{'comment'} && @{$ci->{'comment'}}[0] eq $dummy_commit_msg);

		my ($sha1, $when) = (
			$ci->{'sha1'},
			$ci->{'author_epoch'}
		);

		my @pages;
		foreach my $detail (@{ $ci->{'details'} }) {
			my $file = $detail->{'file'};
			my $efile = join('/',
				map { uri_escape_utf8($_) } split('/', $file)
			);

			my $diffurl = defined $config{'diffurl'} ? $config{'diffurl'} : "";
			$diffurl =~ s/\[\[file\]\]/$efile/go;
			$diffurl =~ s/\[\[sha1_parent\]\]/$ci->{'parent'}/go;
			$diffurl =~ s/\[\[sha1_from\]\]/$detail->{'sha1_from'}/go;
			$diffurl =~ s/\[\[sha1_to\]\]/$detail->{'sha1_to'}/go;
			$diffurl =~ s/\[\[sha1_commit\]\]/$sha1/go;

			push @pages, {
				page => pagename($file),
				diffurl => $diffurl,
			};
		}

		my @messages;
		my $pastblank=0;
		foreach my $line (@{$ci->{'comment'}}) {
			$pastblank=1 if $line eq '';
			next if $pastblank && $line=~m/^ *(signed[ \-]off[ \-]by[ :]|acked[ \-]by[ :]|cc[ :])/i;
			push @messages, { line => $line };
		}

		my $user=$ci->{'author_username'};
		my $web_commit = ($ci->{'author'} =~ /\@web>/);
		my $nickname;

		# Set nickname only if a non-url author_username is available,
		# and author_name is an url.
		if ($user !~ /:\/\// && defined $ci->{'author_name'} &&
		    $ci->{'author_name'} =~ /:\/\//) {
			$nickname=$user;
			$user=$ci->{'author_name'};
		}

		# compatability code for old web commit messages
		if (! $web_commit &&
		      defined $messages[0] &&
		      $messages[0]->{line} =~ m/$config{web_commit_regexp}/) {
			$user = defined $2 ? "$2" : "$3";
			$messages[0]->{line} = $4;
		 	$web_commit=1;
		}

		push @rets, {
			rev        => $sha1,
			user       => $user,
			nickname   => $nickname,
			committype => $web_commit ? "web" : "git",
			when       => $when,
			message    => [@messages],
			pages      => [@pages],
		} if @pages;

		last if @rets >= $num;
	}

	return @rets;
}

sub rcs_diff ($;$) {
	my $rev=shift;
	my $maxlines=shift;
	my ($sha1) = $rev =~ /^($sha1_pattern)$/; # untaint
	my @lines;
	my $addlines=sub {
		my $line=shift;
		return if defined $maxlines && @lines == $maxlines;
		push @lines, $line."\n"
			if (@lines || $line=~/^diff --git/);
		return 1;
	};
	safe_git(
		chdir => $config{srcdir},
		error_handler => undef,
		data_handler => $addlines,
		cmdline => ["git", "show", $sha1],
	);
	if (wantarray) {
		return @lines;
	}
	else {
		return join("", @lines);
	}
}

{
my %time_cache;

sub findtimes ($$) {
	my $file=shift;
	my $id=shift; # 0 = mtime ; 1 = ctime

	if (!exists $time_cache{$file}) {
		my $command = "git log --follow --format=%ct -- \"$config{srcdir}/$file\"";
		my $output = `$command`;
		my @timestamps = $output =~ /(\d+)/g;
		if (@timestamps) {
			my $ctime = $timestamps[-1] or undef;
			my $mtime //= $timestamps[0] or $ctime;
			$time_cache{$file}[1]=$ctime;
			$time_cache{$file}[0]=$mtime;
		}
	}

	return exists $time_cache{$file} ? $time_cache{$file}[$id] : 0;
}

}

sub rcs_getctime ($) {
	my $file=shift;

	return findtimes($file, 1);
}

sub rcs_getmtime ($) {
	my $file=shift;

	return findtimes($file, 0);
}

{
my $ret;
sub git_find_root {
	# The wiki may not be the only thing in the git repo.
	# Determine if it is in a subdirectory by examining the srcdir,
	# and its parents, looking for the .git directory.

	return @$ret if defined $ret;
	
	my $subdir="";
	my $dir=$config{srcdir};
	while (! -d "$dir/.git") {
		$subdir=IkiWiki::basename($dir)."/".$subdir;
		$dir=IkiWiki::dirname($dir);
		if (! length $dir) {
			error("cannot determine root of git repo");
		}
	}

	$ret=[$subdir, $dir];
	return @$ret;
}

}

sub git_parse_changes ($$@) {
	my $dir = shift;
	my $reverted = shift;
	my @changes = @_;

	my ($subdir, $rootdir) = git_find_root();
	my @rets;
	foreach my $ci (@changes) {
		foreach my $detail (@{ $ci->{'details'} }) {
			my $file = $detail->{'file'};

			# check that all changed files are in the subdir
			if (length $subdir &&
			    ! ($file =~ s/^\Q$subdir\E//)) {
				error sprintf(gettext("you are not allowed to change %s"), $file);
			}

			my ($action, $mode, $path);
			if ($detail->{'status'} =~ /^[M]+\d*$/) {
				$action="change";
				$mode=$detail->{'mode_to'};
			}
			elsif ($detail->{'status'} =~ /^[AM]+\d*$/) {
				$action= $reverted ? "remove" : "add";
				$mode=$detail->{'mode_to'};
			}
			elsif ($detail->{'status'} =~ /^[DAM]+\d*/) {
				$action= $reverted ? "add" : "remove";
				$mode=$detail->{'mode_from'};
			}
			else {
				error "unknown status ".$detail->{'status'};
			}

			# test that the file mode is ok
			if ($mode !~ /^100[64][64][64]$/) {
				error sprintf(gettext("you cannot act on a file with mode %s"), $mode);
			}
			if ($action eq "change") {
				if ($detail->{'mode_from'} ne $detail->{'mode_to'}) {
					error gettext("you are not allowed to change file modes");
				}
			}

			# extract attachment to temp file
			if (($action eq 'add' || $action eq 'change') &&
			    ! pagetype($file)) {
				eval q{use File::Temp};
				die $@ if $@;
				my $fh;
				($fh, $path)=File::Temp::tempfile(undef, UNLINK => 1);
				safe_git(
					chdir => $dir,
					error_handler => sub { error("failed writing temp file '$path': ".shift."."); },
					stdout => $fh,
					cmdline => ['git', 'show', $detail->{sha1_to}],
				);
			}

			push @rets, {
				file => $file,
				action => $action,
				path => $path,
			};
		}
	}

	return @rets;
}

sub rcs_receive () {
	my @rets;
	while (<>) {
		chomp;
		my ($oldrev, $newrev, $refname) = split(' ', $_, 3);

		# only allow changes to gitmaster_branch
		if ($refname !~ /^refs\/heads\/\Q$config{gitmaster_branch}\E$/) {
			error sprintf(gettext("you are not allowed to change %s"), $refname);
		}

		# Avoid chdir when running git here, because the changes
		# are in the master git repo, not the srcdir repo.
		# (Also, if a subdir is involved, we don't want to chdir to
		# it and only see changes in it.)
		# The pre-receive hook already puts us in the right place.
		push @rets, git_parse_changes('.', 0, git_commit_info('.', $oldrev."..".$newrev));
	}

	return reverse @rets;
}

sub rcs_preprevert ($) {
	my $rev=shift;
	my ($sha1) = $rev =~ /^($sha1_pattern)$/; # untaint

	my @undo;      # undo stack for cleanup in case of an error

	# Examine changes from root of git repo, not from any subdir,
	# in order to see all changes.
	my ($subdir, $rootdir) = git_find_root();
	ensure_committer($rootdir);

	# preserve indentation of previous in_git_dir code for now
	do {
		my @commits=git_commit_info($rootdir, $sha1, 1);

		if (! @commits) {
			error "unknown commit"; # just in case
		}

		# git revert will fail on merge commits. Add a nice message.
		if (exists $commits[0]->{parents} &&
		    @{$commits[0]->{parents}} > 1) {
			error gettext("you are not allowed to revert a merge");
		}

		# Due to the presence of rename-detection, we cannot actually
		# see what will happen in a revert without trying it.
		# But we can guess, which is enough to rule out most changes
		# that we won't allow reverting.
		git_parse_changes($rootdir, 1, @commits);

		my $failure;
		my @ret;
		eval {
			my $branch = "ikiwiki_revert_${sha1}"; # supposed to be unique

			push @undo, sub {
				run_or_cry_in($rootdir, 'git', 'branch', '-D', $branch) if $failure;
			};
			if (run_or_non_in($rootdir, 'git', 'rev-parse', '--quiet', '--verify', $branch)) {
				run_or_non_in($rootdir, 'git', 'branch', '-D', $branch);
			}
			run_or_die_in($rootdir, 'git', 'branch', $branch, $config{gitmaster_branch});

			my $working = create_temp_working_dir($rootdir, $branch);

			push @undo, sub {
				remove_tree($working);
			};

			run_or_die_in($working, 'git', 'checkout', '--quiet', '--force', $branch);
			run_or_die_in($working, 'git', 'revert', '--no-commit', $sha1);
			run_or_die_in($working, 'git', 'commit', '-m', "revert $sha1", '-a');

			my @raw_lines;
			@raw_lines = run_or_die_in($rootdir, 'git', 'diff', '--pretty=raw',
				'--raw', '--abbrev=40', '--always', '--no-renames',
				"..${branch}");

			my $ci = {
				details => [parse_changed_files($rootdir, \@raw_lines)],
			};

			@ret = git_parse_changes($rootdir, 0, $ci);
		};
		$failure = $@;

		# Process undo stack (in reverse order).  By policy cleanup
		# actions should normally print a warning on failure.
		while (my $handle = pop @undo) {
			$handle->();
		}

		if ($failure) {
			my $message = sprintf(gettext("Failed to revert commit %s"), $sha1);
			error("$message\n$failure\n");
		}
		return @ret;
	};
}

sub rcs_revert ($) {
	# Try to revert the given rev; returns undef on _success_.
	my $rev = shift;
	my ($sha1) = $rev =~ /^($sha1_pattern)$/; # untaint

	ensure_committer($config{srcdir});

	if (run_or_non_in($config{srcdir}, 'git', 'cherry-pick', '--no-commit', "ikiwiki_revert_$sha1")) {
		return undef;
	}
	else {
		run_or_non_in($config{srcdir}, 'git', 'branch', '-D', "ikiwiki_revert_$sha1");
		return sprintf(gettext("Failed to revert commit %s"), $sha1);
	}
}

1
