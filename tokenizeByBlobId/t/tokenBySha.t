#!/usr/bin/env perl

use strict;
use warnings;

use File::Path qw(make_path);
use File::Temp qw(tempdir);
use FindBin qw($Bin);
use IPC::Open3;
use Symbol qw(gensym);
use Test::More;

my $wrapper = "$Bin/../tokenBySha.pl";
my $root = tempdir(CLEANUP => 1);

sub write_executable {
    my ($name, $contents) = @_;
    my $path = "$root/$name";
    open(my $fh, ">", $path) or die "cannot create $path: $!";
    print {$fh} $contents;
    close($fh) or die "cannot close $path: $!";
    chmod(0755, $path) or die "cannot chmod $path: $!";
    return $path;
}

my $echo_tokenizer = write_executable("echo-tokenizer.pl", <<'SCRIPT');
#!/usr/bin/env perl
use strict;
use warnings;
use File::Basename qw(basename);
my $input = $ARGV[-1];
my ($language) = grep { /^--language=/ } @ARGV;
open(my $fh, "<", $input) or die "cannot read $input: $!";
local $/;
my $contents = <$fh>;
close($fh);
print "$language|", basename($input), "\n", $contents;
SCRIPT

my $failing_tokenizer = write_executable("failing-tokenizer.pl", <<'SCRIPT');
#!/usr/bin/env perl
print "partial output must not be memoized\n";
exit 7;
SCRIPT

sub run_wrapper {
    my (%args) = @_;
    make_path($args{memo});
    local %ENV = %ENV;
    $ENV{BFG_BLOB} = "a" x 40;
    $ENV{BFG_FILENAME} = $args{filename};
    $ENV{BFG_PATH} = "src/$args{filename}";
    $ENV{BFG_MEMO_DIR} = $args{memo};
    $ENV{BFG_TOKENIZE_CMD} = $args{command};

    my ($stdin, $stdout);
    my $stderr = gensym;
    my $pid = open3($stdin, $stdout, $stderr, $wrapper);
    print {$stdin} $args{contents};
    close($stdin);
    local $/;
    my $out = <$stdout> // "";
    my $err = <$stderr> // "";
    waitpid($pid, 0);
    return ($? >> 8, $out, $err);
}

my ($status_a, $output_a) = run_wrapper(
    memo => "$root/memo-a",
    filename => "sample.c",
    contents => "union { int value; };\n",
    command => $echo_tokenizer,
);
my ($status_b, $output_b) = run_wrapper(
    memo => "$root/memo-b",
    filename => "sample.c",
    contents => "union { int value; };\n",
    command => $echo_tokenizer,
);
is($status_a, 0, "first clean memo run succeeds");
is($status_b, 0, "second clean memo run succeeds");
is($output_b, $output_a, "independent clean memo directories produce identical output");
like($output_a, qr{--language=C\|blob-[0-9a-f]{40}\.c}, "tokenizer input path is content-derived and stable");
unlike($output_a, qr{tmpfile-in-}, "random input filename is not exposed to tokenizer");

my ($c_status, $c_output) = run_wrapper(
    memo => "$root/memo-extension",
    filename => "same.c",
    contents => "same bytes\n",
    command => $echo_tokenizer,
);
my ($cpp_status, $cpp_output) = run_wrapper(
    memo => "$root/memo-extension",
    filename => "same.cpp",
    contents => "same bytes\n",
    command => $echo_tokenizer,
);
is($c_status, 0, "C cache entry succeeds");
is($cpp_status, 0, "C++ cache entry succeeds");
isnt($cpp_output, $c_output, "extension and language are part of the memo identity");
like($cpp_output, qr{--language=C\+\+}, "C++ invocation is not served from the C memo entry");

my ($failed_status) = run_wrapper(
    memo => "$root/memo-failure",
    filename => "failed.c",
    contents => "retry me\n",
    command => $failing_tokenizer,
);
isnt($failed_status, 0, "tokenizer failure propagates as non-zero");
my ($retry_status, $retry_output) = run_wrapper(
    memo => "$root/memo-failure",
    filename => "failed.c",
    contents => "retry me\n",
    command => $echo_tokenizer,
);
is($retry_status, 0, "same key can be retried after failure");
unlike($retry_output, qr{partial output}, "failed output was not memoized");

my @children;
for my $index (0 .. 3) {
    my $pid = fork();
    die "fork failed: $!" unless defined $pid;
    if ($pid == 0) {
        my ($status, $output) = run_wrapper(
            memo => "$root/memo-concurrent",
            filename => "parallel.c",
            contents => "int parallel;\n",
            command => $echo_tokenizer,
        );
        open(my $fh, ">", "$root/concurrent-$index") or exit 90;
        print {$fh} $output;
        close($fh);
        exit($status);
    }
    push @children, $pid;
}

for my $pid (@children) {
    waitpid($pid, 0);
    is($? >> 8, 0, "concurrent wrapper process succeeds");
}
my @concurrent_outputs;
for my $index (0 .. 3) {
    open(my $fh, "<", "$root/concurrent-$index") or die "cannot read concurrent output: $!";
    local $/;
    push @concurrent_outputs, <$fh>;
    close($fh);
}
for my $index (1 .. $#concurrent_outputs) {
    is($concurrent_outputs[$index], $concurrent_outputs[0], "concurrent output $index matches the first");
}

done_testing();
