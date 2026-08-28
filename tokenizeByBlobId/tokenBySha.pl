#!/usr/bin/env perl

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.


# this program is run by bfg. It does not take any parameters. Instead, it simply reads
# its parameters from the environment

# Env. variables

# BFG_BLOB: the id of the blob (a SHA)
# BFG_FILENAME: basename of the file to process. it has an extension
# BFG_MEMO_DIR: directory of memoized files
# BFG_TOKENIZE_CMD: command to tokenize, might include parameters

# this program must not have any parameters


# it should  get all its parameters from the environment

 
use Digest::SHA qw(sha1_hex);
use DBI;
use File::Temp qw(mkstemp);
use Fcntl qw(:flock);
use strict;
use File::Path qw(make_path);
use File::Copy;
use FindBin qw($RealBin);

# build/ tempdir anchored to the script's dir, not the caller's CWD.
my $buildDir = "$RealBin/build";
make_path($buildDir) if not -d $buildDir;


my %mapLang = (
               "c" => 'C',
               "c++" => 'C++',
               "cc" => 'C++',
               "cp" => 'C++',
               "cpp" => 'C++',
               "cxx" => 'C++',
               "go"  => 'Go',
               "h" => 'C',
               "h++" => 'C++',
               "hh" => 'C++',
               "hpp" => 'C++',
               "java" => 'Java',
               "md" => "Markdown",
               "yaml" => "Yaml",
               "ac" => "M4",
               "am" => "M4",
               "rs" => "Rust",
              );


if (not defined($ENV{BFG_MEMO_DIR}) ||  $ENV{BFG_MEMO_DIR} eq "") {
    die "You must define the environment variable BFG_MEMO_DIR equal to the directory where to memoize"
}

my $shaDir = $ENV{BFG_MEMO_DIR};

if ($shaDir eq "") {
    die "Directory to use to memoize not set. Use BFG_MEMO_DIR environment variable to set"
}

my $tokenizeCmd = $ENV{BFG_TOKENIZE_CMD};

if ($tokenizeCmd eq "") {
    die ("Tokenize command not defined. Use environment variable BFG_TOKENIZE_CMD");
}


die "Sha dir [$shaDir] does not exist" if not -d $shaDir;

my $contents = join( "", <> );

my $blob = $ENV{BFG_BLOB};
my $blobFN = $ENV{BFG_FILENAME};

die "BFG_FILENAME environment variable not set " if $blobFN eq "";

my $fileExt;

if ($blobFN =~ /\.([^.]+)$/) {
    $fileExt = lc($1);
}

if (not defined($mapLang{$fileExt})) {
    die "unknown file extension [$fileExt]";
}

# Cache v2 includes the extension because identical bytes can require
# different language handling. It also deliberately avoids the old
# content-only cache namespace, whose entries may contain declaration names
# derived from a random temporary filename.
my $cacheKey = sha1_hex("cregit-token-v2\0$fileExt\0$contents");
my $dir = $shaDir . '/' . substr($cacheKey, 0,2) . '/' . substr($cacheKey, 2,2);
my $filename = $dir . '/' . $cacheKey;
make_path($dir) if not -d $dir;

# Universal Ctags includes the input filename in hashes used for anonymous
# declaration names. A random tempfile therefore made clean pipeline runs
# produce different Git object ids. Use a stable input path and serialize the
# same cache key across processes so concurrent workers cannot race on it.
my $stableInput = "$buildDir/blob-$cacheKey.$fileExt";
# A fixed set of striped locks avoids leaving one filesystem inode per source
# blob while still serializing identical keys (which always share a prefix).
my $lockPath = "$buildDir/token-lock-" . substr($cacheKey, 0, 2);
open(my $lock, ">>", $lockPath) or die "unable to open tokenization lock [$lockPath]: $!";
flock($lock, LOCK_EX) or die "unable to lock tokenization key [$cacheKey]: $!";

if (-f $filename) {
    open(IN, $filename) || die "unable to open memoized file [$filename]";
    my $contents = join( "", <IN> );
    print $contents;
    close(IN);
    
} else {
  my ($fout, $outfile) = mkstemp( "$buildDir/tmpfile-out-XXXXX" );

  open(my $fh, ">", $stableInput) or die "unable to create stable tokenizer input [$stableInput]: $!";
  print $fh $contents;
  close($fh) or die "unable to close stable tokenizer input [$stableInput]: $!";

  my $langOp = "--language=" . $mapLang{$fileExt};

  open(PROC, "$tokenizeCmd $langOp $stableInput |") or die "unable to execute $tokenizeCmd (verify variable BFG_TOKENIZE_CMD) [$tokenizeCmd]";

  while (<PROC>) {
      print $_;
      print $fout $_;
  }
  my $commandOk = close PROC;
  my $commandStatus = $?;
  close($fout) or die "unable to close tokenizer output [$outfile]: $!";
  if (not $commandOk) {
      unlink($outfile);
      unlink($stableInput);
      die "tokenization command failed for [$stableInput] with status [$commandStatus]";
  }

  move( $outfile, $filename) or die "The move operation to memoized directory failed: $!";

  unlink($stableInput);

}

close($lock) or die "unable to close tokenization lock [$lockPath]: $!";
