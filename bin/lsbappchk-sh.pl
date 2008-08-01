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

my $input_file;
my $journal_file = 'lsbappchk-sh.journal';
my $cmdlist_file = $FindBin::Bin."/../share/appchk/sh-cmdlist-3.2";
my $lsb_ver;

#-----------------------------------------------------------------------

sub BEGIN {
    # Add the lib directory to the @INC to be able to include local modules.
    push @INC, $FindBin::Bin.'/../lib/appchk';
}

## INITIALIZATION ##

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
    else {
        if ( $arg =~ /^-/ || defined $input_file ) {
            print STDERR "Unknown parameter: '$arg'\n\n";
            print STDERR usage();
            exit 1;
        }
        else {
            $input_file = $arg;
        }
    }
}

if ( !defined $input_file ) {
    print STDERR "File name expected.\n\n";
    print STDERR usage();
    exit 1;
}

if ( !defined $lsb_ver ) {
    $lsb_ver = '3.2';
}

sub print_help {
    print "LSB Shell Script Checker v. $VERSION\n\n";

    print usage();
}

sub usage {
    return <<HEREDOC
Usage: $0 --lsb=LSBVER [-o <journal file>] [-c <LSB command list file>] <script>
HEREDOC
}

sub fail {
    my ($msg, $errcode) = @_;
    $errcode = 1 if !defined $errcode;
    
    print STDERR "$msg\n";
    exit $errcode;
}

use ShParser;

#use Parse::Eyapp; # DBG:
#my $grammar_file = 'src/sh.yp';
#my $grammar = read_file($grammar_file);
#Parse::Eyapp->new_grammar(
    #input=>$grammar,
    #classname=>'ShParser',
    #firstline=>0
#);

sub read_file {
    my ($filename) = @_;
    
    my $text;
    
    open FILE, $filename
    and do {
        local $/ = undef;
        $text = <FILE>;
        close FILE;
    };
    fail("Can't read file '$filename'") if !defined $text;
    
    return $text;
}

sub NewShParser {
    
    my $parser = ShParser->new(); # Create a parser

    # Setup hooks
    $parser->YYData->{HOOK_INFO} = {};

    $parser->YYData->{HOOKS}{COMMAND} = \&OnCommand;

    $parser->YYData->{HOOKS}{BAD_FUNC_DEF}  = \&GenHook;
    $parser->YYData->{HOOKS}{SELECT}        = \&GenHook;
    $parser->YYData->{HOOKS}{ANDGREAT}      = \&GenHook;
    $parser->YYData->{HOOKS}{HERESTRING}    = \&GenHook;
    $parser->YYData->{HOOKS}{PROCSUBST}     = \&GenHook;
    $parser->YYData->{HOOKS}{BADNAME}       = \&GenHook;
    $parser->YYData->{HOOKS}{BAD_ASSIGNMENT} = \&GenHook;
    $parser->YYData->{HOOKS}{SDOLLAR}       = \&GenHook;
    $parser->YYData->{HOOKS}{DBRACKET}      = \&GenHook;
    $parser->YYData->{HOOKS}{DPAR}          = \&GenHook;
    $parser->YYData->{HOOKS}{NOT_IO_NUMBER} = \&GenHook;
    $parser->YYData->{HOOKS}{LOOP_DPAR}     = \&GenHook;
    $parser->YYData->{HOOKS}{FOR_VARSEMI}   = \&GenHook;
    
    $parser->YYData->{HOOKS}{EXPANSION} = \&OnExpansion;

    $parser->YYData->{HOOKS}{PARSERERR} = \&OnParserErr;
    $parser->YYData->{HOOKS}{MISCERR}   = \&OnMiscErr;
    
    $parser->YYData->{HOOKS}{FUNCTION} = \&OnFunction;
    
    $parser->YYData->{HOOKS}{S_NEWLINE_IN_COMMENT} = \&OnSNewline_in_comment;
    
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

my $journal_fh; # Journal File Handle

sub report {
	return print { $journal_fh } @_, "\n";
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
    print $msg."\n"; # DBG
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


sub Journal_Init {
    my ( $journal_file ) = @_;
    
    open $journal_fh, ">$journal_file"
        or return complain("Failed to open journal for writing: '$journal_file'");
    
    journal_header();
}

sub Journal_Close {
    journal_footer();
    close $journal_fh;
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
                    ."\nAnyway, the file will be checked as a 'sh' script.";
            return;
        } else {
            tp_result 'FAIL', "$filename: 1: "
                    ."'$cmd' is not a shell interpreter."
                    ."\nAnyway, the file will be checked as a 'sh' script.";
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
    
    return $res;
}

my %function_names = ();

sub OnFunction {
    my $parser = shift;
    my $hookname = shift;
    
    my $funcname = shift;
    
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
    
    my $cmdname = $cmd->[0];
    
    # Assignments also go into this sub
    if ( $cmdname && $cmdname =~ /^([A-Za-z_][A-Za-z_0-9]*)(=|\+=)/ ) {
        if ( $2 eq "+=" ) {
            tp_result 'FAIL', file_pos($parser)
                ."'+=' is a bashism. Should be ".'VAR="${VAR}foo"';
            return;
        } else {
            tp_result 'PASS';
            return;
        }
    }

    # unquote the command name
    if ( defined $cmd->[2] ) {
        $cmdname = ShParser::unquote($cmd->[2]);
        return if not defined $cmdname;
    }
    
    if ( defined $ShParser::reserved{$cmdname} ) {
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
                $param = ShParser::unquote($param);
                next if !defined $param || $param eq "";
                if ( $param eq "==" ) {
                    tp_result 'FAIL', file_pos($parser)
                        ."In arguments of the 'test' command use '=' rather than '=='.";
                    return;
                }
            }
        }

        if ( $cmdname eq "." ) {
            # include: don't handle
        }
        elsif ( $cmdname eq "eval" ) {
            # [Eval is usually used for some tricks, so we can't check it]
        }
        elsif ( $cmdname eq "exec" ) {
            if ( @_ ) {
                $_[0] = [ShParser::unquote($_[0]), 0, $_[0]]; # Make a WORD token
                if ( $_[0] ) {
                    OnCommand($parser, 'COMMAND', @_);
                }
            }
        }
        
        tp_result 'PASS';
        return;
    }
    
    # Bash builtins:
    if ( $cmdname =~ /^$re_bash_builtins$/ ) {
        tp_result 'FAIL', file_pos($parser)
                ."'$cmdname' is a Bash built in command and should not be used in a 'sh' script.";
        return;
    }
    
    if ( defined $function_names{$cmdname} ) {
        tp_result 'PASS';
        return; # This is a function call
    }

    if ( $cmdname =~ /^[^A-Za-z0-9_\[\(]/ ) { # Not a command
        return; # Can't say anything useful
    }
    
    # TODO: filter other frequently used non-LSB commands (considering the LSB version)
    
    tp_result 'FAIL', file_pos($parser)
                ."'$cmdname' isn't included in LSB $lsb_ver.";
}

sub limit_len {
    my ($line) = @_;
    
    if ( length($line) > 120 ) {
        return substr($line, 0,100);
    }
    
    $line =~ s/\s*\n$//s;
    
    return $line;
}

sub GenHook {
    my $parser = shift;
    my $hookname = shift;
    
    if ( $hookname eq "BAD_FUNC_DEF" ) {
        tp_result 'FAIL', file_pos($parser)
                ."The 'function' keyword in the definition of function '"
                .limit_len($_[0])."' should be omitted";
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
                ."NAME token is expected: '".limit_len($_[0])."'.";
    }
    elsif ( $hookname eq "BAD_ASSIGNMENT" ) {
        tp_result 'FAIL', file_pos($parser)
                ."ASSIGNMENT token is expected: '".limit_len($_[0])."'.";
    }
    elsif ( $hookname eq "SDOLLAR" ) {
        # $_[0] - line
        my $quotmode = $_[1];
        
        if ( ($quotmode eq '' || $quotmode eq '$(') && $_[0] =~ /^['"]/ ) {
            if ( $_[0] =~ /^'/ ) {
                tp_result 'FAIL', file_pos($parser)
                    ."ANSI-C Quoting syntax is not portable: '\$".limit_len($_[0])."'.";
            }
            elsif ( $_[0] =~ /^"/ ) {
                tp_result 'FAIL', file_pos($parser)
                    ."Locale Translation syntax is not portable: '\$".limit_len($_[0])."'.";
            }
        }
        elsif ( $_[0] !~ /^[\d\\\/\[\]% ]/ ) {
            tp_result 'WARNING', file_pos($parser)
                    ."It would be better to escape the '\$' character in this case: '\$".limit_len($_[0])."'."
                    .( length($_[0]) eq 1 ? " (There is no such special variable)" : "" )
                    ;
        }
    }
    elsif ( $hookname eq "DBRACKET" ) {
        tp_result 'FAIL', file_pos($parser)
                ."[[...]] syntax is a bashism and not portable.";
    }
    elsif ( $hookname eq "DPAR" ) {
        tp_result 'FAIL', file_pos($parser)
                ."((...)) syntax is a bashism. Use \$((...)) instead, although note"
                ." that this substitutes the value of the expression.";
    }
    elsif ( $hookname eq "LOOP_DPAR" ) {
        tp_result 'FAIL', file_pos($parser)
                ."'".$_[0]." (( ... ))' syntax is a bashism and not portable.";
    }
    elsif ( $hookname eq "FOR_VARSEMI" ) {
        tp_result 'WARNING', file_pos($parser)
                ."According to the standard 'for ".$_[0]."; do' should be replaced with 'for ".$_[0]." do' (semicolon omited).";
    }
    elsif ( $hookname eq "NOT_IO_NUMBER" ) {
        my $str = $_[0];
        if ( $str =~ /^\d+[<>&]+[\/\w_]+/ ) {
            $str = $&;
        }
        tp_result 'FAIL', file_pos($parser)
                ."According to POSIX the part of redirection in line '".limit_len($parser->YYData->{LAST_LINE})
                ."' should be treated as '".limit_len($str)."'. For example, 'dash' will fail here.";
    }
    else {
        print "Unhandled hook '$hookname'.\n";
        #die; # DBG:
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
        my ($line) = @_;
        
        if ( $line =~ /^(BASH_[A-Z]+|DIRSTACK|EUID|FUNCNAME|GROUPS|HOSTFILE|HOSTTYPE|HOSTNAME|MACHTYPE|OLDPWD|OPTERR|OSTYPE|PPID|RANDOM|SHELLOPTS|SHLVL|SECONDS|UID)$/ ) {
            tp_result 'FAIL', file_pos($parser)."The '\$$line' variable has special meaning in bash and may be not set in sh. It would be better not use it.";
            return 0;
        }
        if ( $line eq 'EUID' ) {
            tp_result 'FAIL', file_pos($parser)."Use 'id -u' instead of \$EUID.";
            return 0;
        }
        if ( $line =~ /^[A-Za-z_][A-Za-z_0-9]*\[/ ) {
            tp_result 'FAIL', file_pos($parser)."Arrays are not portable.";
            return 0;
        }
        
        return 1;
    };
    
    if ( $quottype eq '${' ) {
        my $line = ShParser::unquote(\@copy);
        if ( !defined $line ) {
            $line = $copy[0];
            if ( ref($line) ne "" ) { return; }
        }
        
        if ( $line =~ /^[A-Za-z_][A-Za-z_0-9]*\// ) {
            tp_result 'FAIL', file_pos($parser)
                    ."'\${$line}': Pattern replacement is a bashism. Use 'sed' instead.";
            return;
        }
        if ( $line =~ /^[A-Za-z_][A-Za-z_0-9]*(:[^\-=\?\+]|\/)/ ) {
            tp_result 'FAIL', file_pos($parser)."'\${$line}': Unportable parameter expansion.";
            return;
        }
        if ( $line =~ /^!/ ) { # Indirect expansion
            tp_result 'FAIL', file_pos($parser)."'\${$line}' - indirect expansion isn't portable.";
            return;
        }
        &$checkvar($line) or return;
        
        return;
    }
    
    if ( $quottype eq '$' ) {
        my $line = ShParser::unquote(\@copy);
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
        
        foreach my $elem ( @copy ) {
            next if ref $elem ne "";
            if ( $elem =~ /(?<!\$){.*}/s ) {
                tp_result 'WARNING', file_pos($parser)
                        ."Bash brace expansions syntax '{a,b,c}' is not portable: '$elem'";
            }
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
        
        if ( !$parser->YYData->{NO_SUBS_CHECK} ) {
            my $subscript = ShParser::serialize(\@copy);
            my $hook_info = $parser->YYData->{HOOK_INFO};
            
            check_subscript( $hook_info->{FILENAME}, $hook_info->{LINENO}, \$subscript, 'no_subs_check' );
        }
        
        return;
    }
    
    if ( $quottype eq '`' ) {
        return if !@copy;
        
        if ( !$parser->YYData->{NO_SUBS_CHECK} ) {
            my $subscript = ShParser::serialize(\@copy);
            my $hook_info = $parser->YYData->{HOOK_INFO};
            
            check_subscript( $hook_info->{FILENAME}, $hook_info->{LINENO}, \$subscript );
        }
        
        return;
    }
   
    if ( $quottype eq '$((' ) {
        
        return;
    }
    
    if ( $quottype eq '=(' ) {
        my $text = ShParser::serialize(\@copy);
        
        tp_result 'FAIL', file_pos($parser)
                ."Arrays are not portable. Near: =(".limit_len($text).")";
        
        return;
    }
    
    if ( $quottype eq '$[' ) {
        my $text = ShParser::serialize(\@copy);
        
        tp_result 'FAIL', file_pos($parser)
                ."\$[...] syntax is not portable. Near \$[".limit_len($text)."].";
        return;
    }
    
    #die "OnExpansion: *$quottype*"; # DBG: Should not happen
}

sub check_subscript {
    my ($filename, $linenum, $text_ref, $no_subs_check) = @_;
    
    my $parser = NewShParser();

    $parser->YYData->{LINESHIFT} = $linenum - 1;
    $no_subs_check and $parser->YYData->{NO_SUBS_CHECK} = 1;

    $parser->Run( $filename, $text_ref ); # Parse it!
}

sub OnParserErr {
    my $parser = shift;
    my $hookname = shift;
    
    my $token = $parser->YYCurval;
    
    my $line = ( defined $parser->YYData->{LAST_LINE} ? $parser->YYData->{LAST_LINE} : "");
    $line =~ s/\s+$//;
    
    my $what = ( defined $token ? $token->[0] : "End of file" );
    my $near = $what.( defined $parser->YYData->{LINE} ? $parser->YYData->{LINE} : "" );
    $near =~ s/\s+$//;
    
    #my $type = $parser->YYCurtok;
	#$type = "" if !defined $type;
    
    tp_result 'FAIL', file_pos($parser)
            ."Parsing error at '$near' in line '$line'."
            ." This may happen due to some language extention used."
            ." Please, report this case to lsb-appcheck-support\@linuxfoundation.org. Don't forget to attach the corresponding part of the script.";
    
    #my @expected = $parser->YYExpect();
    #print_ref \@expected; # DBG:
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
        .' Line: "'.$comment.'"'
        ;
    
}

## BEGIN ##

read_lsb_cmdlist( $cmdlist_file );

Journal_Init( $journal_file );

my $text = read_file($input_file);

tc_start( $input_file );

    # Check the "shebang" line.
    if ( $text =~ /^#!\/.*/ ) {
        OnShebang( $input_file, $& );
    }
    else {
        tp_result 'PASS';
    }

    my $parser = NewShParser();
    $parser->YYData->{IS_MAIN} = 1;
    
    $parser->Run( $input_file, \$text );   # Parse it!
    
tc_end();    

Journal_Close();

exit 0; # TODO: return 1 if failed
