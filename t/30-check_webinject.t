#!/usr/bin/env perl

use warnings;
use strict;
use Test::More;

BEGIN {
    use lib('t');
    require TestUtils;
    import TestUtils;
    use FindBin;
    use lib "$FindBin::Bin/lib/lib/perl5";
}

plan( tests => 16 );

##################################################
# create our test site
my $omd_bin = TestUtils::get_omd_bin();
my $site    = TestUtils::create_test_site() or BAIL_OUT("no further testing without site");

##################################################
# execute some checks
my $tests = [
  { cmd => $omd_bin." start $site" },

  { cmd => "/bin/su - $site -c 'lib/nagios/plugins/check_webinject'", exit => 3, like => '/find any test case files to run./' },

  { cmd => $omd_bin." stop $site" },
];
for my $test (@{$tests}) {
    TestUtils::test_command($test);
}

##################################################
# cleanup test site
TestUtils::remove_test_site($site);
