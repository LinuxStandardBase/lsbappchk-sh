#!/usr/bin/perl -w
# LSB AppChk for Shell Scripts
#
# Copyright (C) 2008 The Linux Foundation. All rights reserved.
#
# This program has been developed by ISP RAS for LF.
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA 02110-1301, USA.
# # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # # #

use strict;
use FindBin;

my $VERSION = "0.9";

my $input_files = {}; # $input_files->{$file}->{FILENAME, TYPE, JOURNAL};
my @file_order = ();
my $cmdlist_file = $FindBin::Bin."/../share/appchk/sh-cmdlist-4.1";
my $lsb_ver;

#-----------------------------------------------------------------------

sub BEGIN {
	# Add the lib directory to the @INC to be able to include local modules.
	push @INC, $FindBin::Bin.'/../share/appchk';
}

## INITIALIZATION ##
my $fallback_journal_file = "appchk-sh.journal";

my $journal_file = '';
my @args = @ARGV;
while ( @args ) {
	my $arg = shift @args;
	
	if ( $arg eq '-o' ) {
		$journal_file = shift @args;
		defined $journal_file
			or fail("File name expected after '-o'");
	}
	elsif ( $arg eq '-c' ) {
		$cmdlist_file = shift @args;
		defined $cmdlist_file
			or fail("File name expected after '-c'");
	}
	elsif ( $arg eq '--help' || $arg eq '-h' ) {
		print_help();
		exit 0;
	}
	elsif ( $arg eq '--lsb' || ($arg =~ /^--lsb=(.*)/ and unshift @args, $1) ) {
		$lsb_ver = shift @args;
		$cmdlist_file = $FindBin::Bin."/../share/appchk/sh-cmdlist-".$lsb_ver;
	}
	elsif ( $arg eq '--list' ) {
		my $list_file = shift @args;
		read_file_list($list_file) or fail("Failed to read list file '$list_file'");
	}
	else {
		if ( $arg =~ /^-/ ) {
			print STDERR "Unknown parameter: '$arg'\n\n";
			print STDERR usage();
			exit 1;
		}
		else {
			$input_files->{$arg} = { FILENAME => $arg, TYPE => 'SH',
					JOURNAL => $journal_file,
			};
			push @file_order, $arg;
		}
	}
}

if ( !@file_order ) {
	print STDERR "No files to check.\n\n";
	print STDERR usage();
	exit 1;
}

if ( !defined $lsb_ver ) {
	$lsb_ver = '4.1';
}

sub print_help {
	print "LSB Shell Script Checker v. $VERSION\n\n";

	print usage();
}

sub usage {
	return <<HEREDOC
Usage: $0 [--lsb=LSBVER] [-c <LSB command list file>] \\
	[-o <journal file>] <script> [[-o <journal file>] <script> ...]

Batch mode: $0 [--lsb=LSBVER] [-c <LSB commands>] --list <file_list>
HEREDOC
}

sub fail {
	my ($msg, $errcode) = @_;
	$errcode = 1 if !defined $errcode;
	
	print STDERR "$msg\n";
	exit $errcode;
}

sub read_file_list {
	my ($list_file) = @_;
	
	open FILE, $list_file or fail("Failed to open file for reading: '$list_file'");
	while ( my $line = <FILE> ) {
		next if $line =~ /^#/;
		next if $line =~ /^$/;
		
		$line =~ s/[\r\n]+$//g; # chomp
		
		# SH: /application/file \t /journal/file
		if ( $line =~ m/^(SH|BIN):\s*([^\t]+)(\t([^\t]+))?\s*$/ ) {
			my $filetype = $1;
			my $filename = $2;
			my $journal = $4;
			$input_files->{$filename} = { FILENAME => $filename, TYPE => $filetype,
					JOURNAL => $journal
			};
			push @file_order, $filename;
		}
		else {
			print STDERR "Wrong line ($list_file:$.): '$line'\n";
		}
	}
	close FILE;
}

use ShParser;

# Export:
for my $name (qw/serialize unquote limit_len/) {
	$::{$name} = \&{"ShParser::$name"};
}

sub read_file {
	my ($filename) = @_;
	
	my $text;
	
	open FILE, $filename
	and do {
		local $/ = undef;
		$text = <FILE>;
		close FILE;
	};
	( defined $text ) or fail("Can't read file '$filename'");
	
	return $text;
}

sub NewShParser {
	my ($nocheck) = @_;
	
	my $parser = ShParser->new(); # Create a parser

	# Setup hooks
	$parser->YYData->{HOOK_INFO} = {};
	
	$parser->YYData->{HOOKS}{FUNCTION} = \&OnFunction;
	
	unless ( $nocheck ) {
		$parser->YYData->{HOOKS}{COMMAND} = \&OnCommand;

		$parser->YYData->{HOOKS}{BAD_FUNC_DEF}   = \&GenHook;
		$parser->YYData->{HOOKS}{SELECT}         = \&GenHook;
		$parser->YYData->{HOOKS}{ANDGREAT}       = \&GenHook;
		$parser->YYData->{HOOKS}{HERESTRING}     = \&GenHook;
		$parser->YYData->{HOOKS}{PROCSUBST}      = \&GenHook;
		$parser->YYData->{HOOKS}{BADNAME}        = \&GenHook;
		$parser->YYData->{HOOKS}{ASSIGNMENT_WORD} = \&GenHook;
		$parser->YYData->{HOOKS}{SDOLLAR}        = \&GenHook;
		$parser->YYData->{HOOKS}{DPAR}           = \&GenHook;
		$parser->YYData->{HOOKS}{NOT_IO_NUMBER}  = \&GenHook;
		$parser->YYData->{HOOKS}{LOOP_DPAR}      = \&GenHook;
		$parser->YYData->{HOOKS}{FOR_VARSEMI}    = \&GenHook;
		$parser->YYData->{HOOKS}{EXTGLOB}        = \&GenHook;
		$parser->YYData->{HOOKS}{CRLF}           = \&GenHook;
		
		$parser->YYData->{HOOKS}{EXPANSION}      = \&OnExpansion;

		$parser->YYData->{HOOKS}{PARSERERR}      = \&OnParserErr;
		$parser->YYData->{HOOKS}{MISCERR}        = \&OnMiscErr;
		
		$parser->YYData->{HOOKS}{S_NEWLINE_IN_COMMENT} = \&OnSNewline_in_comment;
	}
	
	return $parser;
}

#-----------------------------------------------------------------------

my %commands = (
	# special builtins
	# Parameters are supposed to be listed in brackets in future.
	'break' => [],
	':' => [],
	'continue' => [],
	'.' => [],
	'eval' => [],
	'exec' => [],
	'exit' => [],
	'export' => [],
	'readonly' => [],
	'return' => [],
	'set' => [],
	'shift' => [],
	'times' => [],
	'trap' => [],
	'unset' => [],
);

sub read_lsb_cmdlist {
	my ($filename) = @_;
	open CMDS, $filename;
	
	while ( my $line = <CMDS> ) {
		next if $line =~ /^\s*#/;
		chomp $line;
		$line =~ s/^\s+//; # Trim spaces
		$line =~ s/\s+$//;
		next if $line eq "";
		
		if ( $line =~ /^(\S+)(\s+.*)?$/ ) {
			my $params = [];
			if ( defined $2 ) {
				push @$params, split /\s+/, $2;
			}
			$commands{$1} = $params;
		} else {
			fail("Wrong line in '$filename': '$line'");
		}
	}
	
	close CMDS;
}

#-----------------------------------------------------------------------

# TET Journal Stuff

my %result_code = (
		PASS => 0,
		FAIL => 1,
		UNRESOLVED => 2,
		WARNING => 101,
		FIP => 102,
	);

my $journal_fh; # File handle of the current journal
my $current_journal = "";

sub report {
	return print {$journal_fh} @_, "\n";
}

sub tet_line {
	my ($code, $mid, $msg, $is_info ) = @_;
	
	$msg = "" if !defined $msg;
	
	$mid =~ s/[\r\n\t]/ /sg;
	
	my $pref = $code."|".$mid;
	
	if ( !$is_info ) {
		$msg =~ s/[\r\n]/ /sg;
		
		my $line = $pref."|".$msg;
		
		return $line;
	}
	else {
		my $res = "";
		my $seq = 1;
		
		while ( $msg =~ m/\G[^\r\n]*([\r\n]|\z)/sg ) {
			last if $& eq "";
			my $line = $pref." $seq|".$&;
			++$seq;
			$res .= $line;
		}
		return $res;
	}
}

sub test_time {
	my ($full) = @_;
	
	my ($sec,$min,$hour,$mday,$mon,$year)=localtime;
	$year += 1900;
	if ( $full ) {
		return sprintf("%02d:%02d:%02d %04d%02d%02d", $hour, $min, $sec, $year, $mon+1, $mday);
	} else {
		return sprintf("%02d:%02d:%02d", $hour, $min, $sec);
	}
}

sub journal_header {
	my $login = getpwuid($<);
	report tet_line 0, "3.7-lite ".test_time(1),  "User: ". $login.", Command line: ".$0; 
	
	my $uname = `uname -snrvm`; chomp $uname;
	report tet_line 5, $uname, "System Information";

	report tet_line 30, "", "VSX_NAME=".$VERSION;
	report tet_line 40, "", "Config End";
}

my $activity = 0;
my $test_point = 1;

sub tc_start {
	my ($testname) = @_;
	
	report tet_line 10, $activity." ".$testname." ".test_time(), "TC Start";
	
	$test_point = 1;
}

sub tp_start {
	report tet_line 200, $activity." ".$test_point." ".test_time(), "TP Start";
}

sub test_comment {
	my ($msg) = @_;
	
	report tet_line(520, $activity." ".$test_point." 0 0", $msg, 1);
}

sub tp_end {
	my ($result) = @_;
	
	my $code = $result_code{$result};
	
	report tet_line 220, $activity." ".$test_point." ".$code." ".test_time(), $result;
	
	++$test_point;
}

sub tp_result {
	my ($result, $msg) = @_;
	
	tp_start();
	if ( defined $msg ) {
		test_comment($msg);
		print '['.$result.'] '.$msg."\n"; # DBG
	}
	tp_end($result);
}

sub tc_end {
	report tet_line 80, $activity." 0 ".test_time(), "TC End";
	++$activity;
}

sub journal_footer {
	report tet_line 900, test_time(), "TCC End";
}

my $default_jfh = undef; # File handle for fallback journal

sub default_journal_init {
	if ( !$default_jfh ) {
		open $default_jfh, ">$fallback_journal_file"
			or die "Failed to open journal for writing: '$fallback_journal_file'";
		$journal_fh = $default_jfh;
		journal_header();
	} else {
		$journal_fh = $default_jfh;
	}
	$current_journal = $fallback_journal_file;
}

sub Journal_Init {
	my ( $journal_file ) = @_;
	
	if ( -f $journal_file ) {
		print STDERR "Warning! Overwriting file '$journal_file'\n";
	}
	$journal_fh = undef;
	open $journal_fh, ">$journal_file"
		or die "Failed to open journal for writing: '$journal_file'";
	$current_journal = $journal_file;
	
	journal_header();
}

sub Journal_Close {
	
	journal_footer();
	
	close $journal_fh;
	
	$journal_fh = undef;
}

sub END { # finalize the default journal on exit
	local $?;
	if ( $journal_fh ) {
		if ( $default_jfh && $default_jfh != $journal_fh ) {
			Journal_Close();
			$journal_fh = $default_jfh;
		}
		Journal_Close();
	}
}
#-----------------------------------------------------------------------

# Syntax Hooks

sub OnShebang {
	my ($filename, $line) = @_;
	
	$line =~ s/[\s\n\r]+$//s; # remove trailing spaces and newlines
	$line =~ s/^#!//; # remove #!
	$line =~ s/^\s+//;
	
	my $cmd = "";
	if ( $line =~ m{/([^/]*)$} ) {
		$cmd = $1;
	}
	
	$cmd =~ s/\s.*//g; # remove shell parameters if any
	
	if ( $cmd !~ /^sh$/ ) {
		if ( $cmd =~ /sh$/ ) {
			tp_result 'FAIL', "$filename: 1: "
					."The '$cmd' shell is not included in LSB."
					." You should port the script to the 'sh' language."
					." Anyway, the file will be checked as a 'sh' script.";
			return;
		} else {
			tp_result 'FAIL', "$filename: 1: "
					."'$cmd' is not a shell interpreter."
					." Anyway, the file will be checked as a 'sh' script.";
			return;
		}
	} else {
		unless ( $line =~  m{^/bin/[^/]+$} ) {
			tp_result 'FAIL', "$filename: 1: "
					."Probably should be '#!/bin/$cmd' here.";
			return;
		}
	}
	tp_result 'PASS';
}

sub file_pos {
	my ($parser) = @_;
	
	my $hook_info = $parser->YYData->{HOOK_INFO};
	
	my $res = "";
	
	$res .= $hook_info->{FILENAME}.": ";
	$res .= $hook_info->{LINENO}.": " if $hook_info->{LINENO};
	
	# $linenum may be undefined in case of syntax error
	
	return $res;
}

sub find_input_file ($) {
	my ($filename) = @_;
	
	while ( $filename =~ s{(^|.*/)\.\.?/}{} ) {}; # remove ../ or ./, thus leave only a distinct part of the path
	my $l = length($filename);
	
	# Since the current path isn't known, compare only the ends of file locations.
	# For example ./../foo/bar would match /var/opt/foo/bar.
	
	foreach my $input_file ( keys %$input_files ) {
		my $tmp = $input_file;
		if ( $filename eq substr($tmp, -$l) ) {
			# compare string ends
			return $input_file;
		}
	}
	
	return undef; # nothing found
}

my %function_names = ();

sub OnFunction {
	my $parser = shift;
	my $hookname = shift;
	
	my $funcname = serialize($_[0]);
	
	$function_names{$funcname} = 1;
}

my @bash_builtins = qw(
		\(\(
		builtin caller declare enable hash help let local logout shopt source typeset ulimit
		dirs pushd popd
		bg fg jobs disown suspend
		compgen complete
		fc history
	);

my $re_bash_builtins = "(".(join "|", map { my $a=$_; $a=~s/[\(\)\[\]\|\\\/\+\?\.\*]/\\$&/g; $a } @bash_builtins).")";

sub OnCommand {
	my $parser = shift;
	my $hookname = shift;
	
	my $cmd = shift;
	# @_ - command parameters
	
	my $cmdname;
	if ( defined $cmd->[1] ) {
		$cmdname = serialize($cmd->[1]);
	}
	
	# unquote the command name
	if ( defined $cmd->[1] ) {
		$cmdname = unquote($cmd->[1]);
		return if not defined $cmdname;
	}
	
	if ( defined $ShParser::{reserved}{$cmdname} ) {
		# The parser has mistaken
		return;
	}
	
	if ( defined $commands{$cmdname} ) { # good commands
		my $params_good = $commands{$cmdname};
		if ( ref($params_good) eq "ARRAY" && @$params_good ) {
			# TODO: check params
		}
		
		if ( $cmdname eq "test" ) {
			# Check params
			foreach my $param ( @_ ) {
				$param = unquote($param);
				next if !defined $param || $param eq "";
				if ( $param eq "==" ) {
					tp_result 'FAIL', file_pos($parser)
						."In arguments of the 'test' command use '=' rather than '=='.";
					return;
				}
			}
		}
		elsif ( $cmdname eq "." ) { # The "dot" operator
			my ($param) = @_;
			$param = unquote($param);
			if ( $param ) {
				my $filename = find_input_file($param);
				if ( !$filename ) {
					if ( $param eq '/lib/lsb/init-functions' ) { tp_result 'PASS'; return; }
					if ( $param eq '/usr/lib/lsb/install_initd' ) { tp_result 'PASS'; return; }
					if ( $param eq '/usr/lib/lsb/remove_initd' ) { tp_result 'PASS'; return; }
					tp_result 'FIP', file_pos($parser)
						."Unknown file was included via the dot operator: '. ".limit_len($param)."'";
					return;
				}
				my $res = check_file( $input_files->{$filename}, 0 ); # parse, but do not check
				if ( !defined $res ) {
					tp_result 'WARNING', file_pos($parser)
						."Possible loop including.";
				}
			}
		}
		elsif ( $cmdname eq "eval" ) {
			# [Eval is usually used for doing tricks, so don't check it at all]
		}
		elsif ( $cmdname eq "exec" ) {
			if ( serialize($_[0]) ) {
				$_[0] = [0, $_[0]]; # Make a WORD token
				if ( $_[0] ) {
					OnCommand($parser, 'COMMAND', @_);
				}
				
				# If exec is specified with command, it shall replace the shell
				# with command without creating a new process.
				
				# Check unconditional exit
				my $i = 0;
				while ( $parser->{STACK}[$i] && !defined $parser->{STACK}[$i][1] ) { $i++ };
				if ( $parser->{STACK}[$i][1][1]
					&& serialize($parser->{STACK}[$i][1][1]) eq $cmdname ) 
				{
					if ( $parser->YYData->{INPUT} !~ /^\s*$/s ) {
						tp_result 'FIP', file_pos($parser)
							."Unconditional exit faced (exec). Stop parsing.";
						$parser->YYData->{INPUT} = ""; # clean up the rest of the script
					}
				}
			}
		}
		elsif ( $cmdname eq "exit" ) {
			# Check unconditional exit
			my $i = 0;
			while ( $parser->{STACK}[$i] && !defined $parser->{STACK}[$i][1] ) { $i++ };
			if ( $parser->{STACK}[$i][1][1]
				&& serialize($parser->{STACK}[$i][1][1]) eq $cmdname )
			{
				if ( $parser->YYData->{INPUT} !~ /^\s*$/s ) {
					tp_result 'FIP', file_pos($parser)
						."Unconditional exit faced. Stop parsing.";
					$parser->YYData->{INPUT} = ""; # clean up the rest of the script
				}
			}
		}
		
		tp_result 'PASS';
		return;
	}
	
	if ( defined $function_names{$cmdname} ) {
		tp_result 'PASS';
		return; # This is a function call
	}
	
	if ( find_input_file($cmdname) ) {
		tp_result 'PASS';
		return; # Internal application component called
	}
	
	# Bash builtins:
	if ( $cmdname =~ /^$re_bash_builtins$/ ) {
		tp_result 'FAIL', file_pos($parser)
				."'$cmdname' is a Bash built in command and should not be used in a 'sh' script.";
		return;
	}
	
	if ( $cmdname =~ /^[^A-Za-z0-9_\[\(\)\]]/ ) { # Not a command
		return; # Can't say anything useful
	}
	
	tp_result 'FAIL', file_pos($parser)
				."'".limit_len($cmdname)."' isn't included in LSB $lsb_ver.";
}

sub GenHook {
	my $parser = shift;
	my $hookname = shift;
	
	if ( $hookname eq "BAD_FUNC_DEF" ) {
		tp_result 'FAIL', file_pos($parser)
				."The 'function' keyword in the definition of function '"
				.limit_len(serialize($_[0]))."' should be omitted";
	}
	elsif ( $hookname eq "SELECT" ) {
		tp_result 'FAIL', file_pos($parser)
				."'select' is a bashism. Don't use it.";
	}
	elsif ( $hookname eq "ANDGREAT" ) {
		tp_result 'FAIL', file_pos($parser)
				."'&>' is a bashism. Should be '>filename 2>&1'";
	}
	elsif ( $hookname eq "HERESTRING" ) {
		tp_result 'FAIL', file_pos($parser)
				."Here-string syntax ('<<<') is a bashism.";
	}
	elsif ( $hookname eq "PROCSUBST" ) {
		tp_result 'FAIL', file_pos($parser)
				."Process substitution ('<(list)') is a bashism.";
	}
	elsif ( $hookname eq "BADNAME" ) {
		tp_result 'FAIL', file_pos($parser)
				."NAME token is expected: '".limit_len(serialize($_[0]))."'.";
	}
	elsif ( $hookname eq "ASSIGNMENT_WORD" ) {
		my $str = serialize($_[0]);
		if ( $str =~ m/^\w+(\[[^\]]*\])?(\+)?=/ ) {
			if ( defined $1 ) {
				tp_result 'FAIL', file_pos($parser)
					."Arrays are not portable. Near: '".limit_len($str)."'.";
			}
			if ( defined $2 ) {
				tp_result 'FAIL', file_pos($parser)
					."'+=' is a bashism. Should be ".'VAR="${VAR}foo"';
			}
		}
		# else: VAR=(...) - was already reported at expansion of =(...)
	}
	elsif ( $hookname eq "SDOLLAR" ) {
		my $str = serialize($_[0]);
		my $quotmode = $_[1];
		
		if ( ($quotmode eq '' || $quotmode eq '$(') && $str =~ /^['"]/ ) {
			if ( $str =~ /^'/ ) {
				tp_result 'FAIL', file_pos($parser)
					."ANSI-C Quoting syntax is not portable: '\$".limit_len($str)."'.";
			}
			elsif ( $str =~ /^\"/ ) {
				tp_result 'FAIL', file_pos($parser)
					."Locale Translation syntax is not portable: '\$".limit_len($str)."'.";
			}
		}
		elsif ( $str !~ /^[\d\\\/\[\]% ]/ ) {
			tp_result 'WARNING', file_pos($parser)
					."It would be better to escape the '\$' character in this case: '\$".limit_len($str)."'."
					.( length($str) eq 1 ? " (There is no such special variable)" : "" )
					;
		}
	}
	elsif ( $hookname eq "DPAR" ) {
		tp_result 'FAIL', file_pos($parser)
				."((...)) syntax is a bashism. Use \$((...)) instead, although note"
				." that this substitutes the value of the expression.";
	}
	elsif ( $hookname eq "LOOP_DPAR" ) {
		tp_result 'FAIL', file_pos($parser)
				."'".serialize($_[0])." (( ... ))' syntax is a bashism and not portable.";
	}
	elsif ( $hookname eq "FOR_VARSEMI" ) {
		tp_result 'WARNING', file_pos($parser)
				."According to the standard 'for ".limit_len(serialize($_[0]))."; do' should be replaced with 'for ".limit_len(serialize($_[0]))." do' (semicolon omited).";
	}
	elsif ( $hookname eq "NOT_IO_NUMBER" ) {
		my $str = serialize($_[0]);
		if ( $str =~ /^\d+[<>&]+[\/\w_]+/ ) {
			$str = $&;
		}
		tp_result 'FAIL', file_pos($parser)
				."According to POSIX the part of redirection in line '".limit_len($parser->YYData->{LAST_LINE})
				."' should be treated as '".limit_len($str)."'. For example, 'dash' will fail here.";
	}
	elsif ( $hookname eq "CRLF" ) {
		if ( !$parser->YYData->{CRLF_REPORTED} ) { # To avoid reporting this error for each line.
			tp_result 'FAIL', file_pos($parser)
				.'CRLF linebreak isn\'t supported by sh. Line: "'.limit_len(serialize($_[0])).'"';
			$parser->YYData->{CRLF_REPORTED} = 1;
		}
	}
	elsif ( $hookname eq "EXTGLOB" ) {
		tp_result 'FAIL', file_pos($parser)
					."Extended patterns are not portable.";
	}
	else {
		print "Unhandled hook '$hookname'.\n";
	}
}

sub OnExpansion {
	my $parser = shift;
	my $hookname = shift;
	my $struct = shift;
	
	my @copy = @$struct;
	
	my $quottype = shift @copy;
	pop @copy;
	
	my $checkvar = sub {
		# This sub is used for parameter expansion such as $VAR and ${VAR}
		my ($line) = @_;
		
		if ( $line =~ s/^(\w*)\[/$1/ ) {
			tp_result 'FAIL', file_pos($parser)."Arrays are not portable.";
		}
		
		if ( $line eq 'EUID' ) {
			tp_result 'FAIL', file_pos($parser)."Use 'id -u' instead of \$EUID.";
		}
		elsif ( $line eq '_' ) {
			tp_result 'FAIL', file_pos($parser)
				."\$_ is not described in the shell language standard, but it works in both bash and dash.";
		}
		elsif ( $line =~ /^(BASH_[A-Z]+|DIRSTACK|EUID|FUNCNAME|GROUPS|HOSTFILE|HOSTTYPE|HOSTNAME|MACHTYPE|OLDPWD|OPTERR|OSTYPE|PPID|RANDOM|SHELLOPTS|SHLVL|SECONDS|UID)$/ ) {
			tp_result 'FAIL', file_pos($parser)."The '\$$line' variable has special meaning in bash and may be not set in sh. It would be better not use it.";
		}
	};
	
	if ( $quottype eq '${' ) {
		my $line = serialize(\@copy);
		if ( !defined $line ) {
			$line = $copy[0];
			if ( ref($line) ne "" ) { return; }
		}
		
		if ( $line =~ /^[A-Za-z_][A-Za-z_0-9]*[#%]/ ) {
			# OK, do nothing
		}elsif ( $line =~ /^[A-Za-z_][A-Za-z_0-9]*\// ) {
			tp_result 'FAIL', file_pos($parser)
					."'\${$line}': Pattern replacement is a bashism. Use 'sed' instead.";
		}elsif ( $line =~ m/\Q^[A-Za-z_A-Za-z_0-9]+(:?+[^\-=\?\+\[]|\/)\E/ ) {
			tp_result 'FAIL', file_pos($parser)."'\${$line}': Unportable parameter expansion or bad substitution.";
		}
		
		if ( $line =~ /^!/ ) { # Indirect expansion
			tp_result 'FAIL', file_pos($parser)."'\${$line}' - indirect expansion isn't portable.";
		}
		
		if ( $line =~ s/\Q^!?(\w+(\[.*)?+)[:\-=\?\+\/]?.*\E/$1/ ) {
			&$checkvar($line);
		}
		
		return;
	}
	
	if ( $quottype eq '$' ) {
		my $line = serialize(\@copy);
		return if not defined $line;
		
		&$checkvar($line);
		
		return;
	}
	
	if ( $quottype eq '' ) {
		return if !@copy;
		
		if ( ref($copy[0]) eq "" ) {
			if ( $copy[0] =~ /^(~([\+\-]|\d+))/ ) {
				tp_result 'FAIL', file_pos($parser)
						."Wrong tilde expansion: '$1'. Only '~' and '~login' are supported.";
			}
		}
		
		my $str = "";
		foreach my $elem ( @copy ) {
			next if ref $elem ne "";
			$str .= $elem;
		}
		if ( $str =~ m/(?<!\$){[^{]*(,|\.\.)[^{]*}/ ) {
			tp_result 'FAIL', file_pos($parser)
						."Bash brace expansion syntax '{a,b,c}' is not portable: '$str'";
		}
		
		return;
	}

	if ( $quottype eq '$(' ) {
		return if !@copy;
		
		if ( ref($copy[0]) eq "" ) {
			if ( $copy[0] =~ /^</ ) {
				tp_result 'FAIL', file_pos($parser)
					."'\$(< file)' is a bashism. Should be \$(cat file).";
				return;
			}
		}
		
		my $subscript = serialize(\@copy);
		my $hook_info = $parser->YYData->{HOOK_INFO};
		
		check_subscript( $hook_info->{FILENAME}, $hook_info->{LINENO}, \$subscript, 'no_subs_check' );
		
		return;
	}
	
	if ( $quottype eq '`' ) {
		return if !@copy;
		
		my $subscript = serialize(\@copy);
		my $hook_info = $parser->YYData->{HOOK_INFO};
		
		check_subscript( $hook_info->{FILENAME}, $hook_info->{LINENO}, \$subscript );
		
		return;
	}
   
	if ( $quottype eq '$((' || $quottype eq '((' ) {
		
		return;
	}
	
	if ( $quottype eq '=(' ) {
		my $text = serialize($struct);
		
		tp_result 'FAIL', file_pos($parser)
				."Arrays are not portable. Near: '".limit_len($text)."'.";
		
		return;
	}
	
	if ( $quottype eq '$[' ) {
		my $text = serialize($struct);
		
		tp_result 'FAIL', file_pos($parser)
				."\$[...] syntax is not portable. Near '".limit_len($text)."'.";
		return;
	}
	
	if ( $quottype eq '[[' ) {
		my $text = serialize($struct);
		
		tp_result 'FAIL', file_pos($parser)
				."[[...]] syntax is a bashism and not portable. Near '".limit_len($text)."'.";
		return;
	}
	
	if ( $quottype =~ /^[\?\*\+\@\!]\(/ ) {
		my $text = serialize($struct);
		
		tp_result 'FAIL', file_pos($parser)
						."Extended patterns are not portable. Near '".limit_len($text)."'";
		return;
	}
	
	die "OnExpansion: *$quottype*"; # DBG: Should not happen
}

sub check_subscript {
	my ($filename, $linenum, $text_ref, $no_subs_check) = @_;
	
	my $parser = NewShParser();

	$parser->YYData->{LINESHIFT} = $linenum - 1;

	$parser->Run( $filename, $text_ref ); # Parse it!
}

sub OnParserErr {
	my $parser = shift;
	my $hookname = shift;
	
	my $token = $parser->YYCurval;
	
	my $line = ( defined $parser->YYData->{LAST_LINE} ? $parser->YYData->{LAST_LINE} : "");
	$line =~ s/\s+$//;
	
	my $what = ( defined $token ? serialize($token->[1]) : "End of script" ) || "";
	my $near = $what.( defined $parser->YYData->{LINE} ? $parser->YYData->{LINE} : "" );
	$near =~ s/\s+$//;
	
	tp_result 'FAIL', file_pos($parser)
			."Parsing error at '$near' in line '$line'."
			." This may happen due to some language extention used."
			." Please, report this case to lsb-appcheck-support\@linuxfoundation.org."
			." Don't forget to attach the corresponding part of the script.";
}

sub OnMiscErr {
	my $parser = shift;
	my $hookname = shift;
	my $msg = shift;
	
	tp_result 'FAIL', file_pos($parser).$msg;
}

sub OnSNewline_in_comment {
	my $parser = shift;
	my $hookname = shift;
	my $comment = shift;
	
	tp_result 'WARNING', file_pos($parser)
		.' Comment line ends with backslash. According to POSIX it means'
		.' that the comment would be expanded to the next line. Actually, bash (as well as other shells) doesn\'t behave this way.'
		.' But it would be better to remove backslash from the end of the line or add a space after it.'
		.' Line: "'.limit_len($comment).'"';
	
}

my @include_stack = ();

sub check_file ($$) {
	my ($file, $check) = @_;
	
	my $filename = $file->{FILENAME};
	
	foreach my $included ( @include_stack ) {
		if ( $included eq $filename ) { # ring including
			return undef;
		}
	}
	push @include_stack, $filename;

	my $text = read_file($filename);

	if ( $check ) {
		# The "shebang" line is actually just a comment,
		# it will be skipped by the parser. So check it manually:
		if ( $text =~ /^(#!\/.*)/ ) {
			OnShebang( $filename, $1 );
		} else {
			tp_result 'PASS'; # put PASS result to have at least one in the journal. (App-checker feels nervous about empty journals.)
		}
	}

	my $parser = NewShParser( !$check );
	
	$parser->Run( $filename, \$text );   # Parse it!
	
	pop @include_stack;
	
	return 1;
}

## BEGIN ##

read_lsb_cmdlist( $cmdlist_file );

for my $filename ( @file_order ) {
	my $file = $input_files->{$filename};
	next if $file->{TYPE} ne 'SH';
	
	print "TESTING: $filename\n"; # For AppChecker
	
	if ( $journal_fh && $file->{JOURNAL} ne $current_journal ) {
		# Close the previous journal
		unless ( $default_jfh && $journal_fh == $default_jfh ) { # never close the default journal
			Journal_Close();
		}
	}
	if ( !$journal_fh || $file->{JOURNAL} ne $current_journal ) {
		# Start a new journal
		if ( !$file->{JOURNAL} ) {
			default_journal_init();
		} else {
			Journal_Init( $file->{JOURNAL} )
				or print STDERR "Skipping '$filename'\n" and next;
		}
	}
	
	# Start the file section
	tc_start( $filename );
	
	# Check the file
	check_file( $file, 1 );
	
	# finish the file section
	tc_end();
	
	# Reset the %function_names
	%function_names = ();
	@include_stack = (); # should be empty, but clear it too just in case.
}

exit 0;
