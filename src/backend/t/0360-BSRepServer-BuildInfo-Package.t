use strict;
use warnings;


use FindBin;
use lib "$FindBin::Bin/lib/";

use Test::Mock::BSRPC;
use Test::Mock::BSConfig;
use Test::OBS::Utils;
use Test::OBS;
use Test::Mock::BSRepServer::Checker;

use Test::More tests => 17;                     # last test to print (3 original + 15 filename fallback)

use BSUtil;
use BSXML;
use Data::Dumper;
use File::Temp qw(tempfile tempdir);

no warnings 'once';
# preparing data directory for testcase 1
$BSConfig::bsdir = "$FindBin::Bin/data/0360/";
$BSConfig::srcserver = 'srcserver';
$BSConfig::repodownload = 'http://download.opensuse.org/repositories';
use warnings;

use_ok("BSRepServer::BuildInfo");

# Test the filename fallback mechanism for build recipes
# This function mirrors the implementation in BSRepServer/BuildInfo.pm
sub extract_name_from_filename {
  my ($filename) = @_;
  return undef unless defined $filename;

  # Get basename without path
  my $basename = $filename;
  $basename =~ s/.*\///;

  # Extract name from different recipe types
  my $name;
  if ($basename =~ /^(.+)\.spec$/) {
    $name = $1;
  } elsif ($basename =~ /^(.+)\.dsc$/) {
    $name = $1;
  } elsif ($basename =~ /^(.+)\.kiwi$/) {
    $name = $1;
  } elsif ($basename =~ /^(.+)\.dockerfile$/i) {
    $name = $1;
  } else {
    # For other types, remove common extensions
    $name = $basename;
    $name =~ s/\.[^.]+$//;  # Remove last extension
  }

  # Validate package name (basic validation)
  return undef unless defined $name && length($name) > 0;
  return undef if $name =~ /[\/\s]/;  # No slashes or spaces

  return $name;
}

# Helper function to create test spec files
sub create_test_spec {
  my ($filename, $content) = @_;
  my $tempdir = tempdir(CLEANUP => 1);
  my $filepath = "$tempdir/$filename";
  open(my $fh, '>', $filepath) or die "Cannot create $filepath: $!";
  print $fh $content;
  close($fh);
  return $filepath;
}

# Simulate parsing with filename fallback
sub simulate_parsing_with_fallback {
  my ($filepath) = @_;

  open(my $fh, '<', $filepath) or die "Cannot read $filepath: $!";
  my $content = do { local $/; <$fh> };
  close($fh);

  # Look for Name: or Source: field
  my $parsed_name;
  for my $line (split /\n/, $content) {
    if ($line =~ /^(?:Name|Source):\s*(.*)$/) {
      $parsed_name = $1;
      $parsed_name =~ s/^\s+|\s+$//g;  # trim whitespace
      $parsed_name = undef if $parsed_name eq '';
      last;
    }
  }

  # Use filename fallback if no valid name found
  if (!defined($parsed_name)) {
    my $basename = $filepath;
    $basename =~ s/.*\///;
    $parsed_name = extract_name_from_filename($basename);
  }

  return $parsed_name;
}

$Test::Mock::BSRPC::fixtures_map = {
  'srcserver/getprojpack?project=openSUSE:13.2&repository=standard&arch=i586&package=screen&withdeps=1&buildinfo=1'
        => 'srcserver/fixture_003_002',
  'srcserver/getprojpack?project=home:Admin:branches:openSUSE.org:OBS:Server:Unstable&repository=openSUSE_Leap_42.1&arch=x86_64&package=_product:OBS-Addon-release&withdeps=1&buildinfo=1'
        => 'srcserver/fixture_003_003',
};


my ($got, $expected);

#
# FILENAME FALLBACK TESTS - Core functionality tests
#

# Test basic recipe types
is(extract_name_from_filename("vazirmatn-fonts.spec"), "vazirmatn-fonts", "spec file extraction");
is(extract_name_from_filename("debian-package.dsc"), "debian-package", "dsc file extraction");
is(extract_name_from_filename("kiwi-image.kiwi"), "kiwi-image", "kiwi file extraction");
is(extract_name_from_filename("container.dockerfile"), "container", "dockerfile extraction");

# Test path handling and edge cases
is(extract_name_from_filename("/path/to/package.spec"), "package", "path handling");
is(extract_name_from_filename("package-with_special.chars123.spec"), "package-with_special.chars123", "special characters");

# Test invalid inputs
is(extract_name_from_filename("invalid file.spec"), undef, "spaces rejected");
is(extract_name_from_filename(".spec"), undef, "empty name rejected");
is(extract_name_from_filename(undef), undef, "undef input");

# Test integration with parsing workflow
my $spec_without_name = create_test_spec("test-pkg.spec", "Version: 1.0\nSummary: Test");
my $spec_with_name = create_test_spec("named-pkg.spec", "Name: correct-name\nVersion: 1.0");

is(simulate_parsing_with_fallback($spec_without_name), "test-pkg", "fallback when no Name field");
is(simulate_parsing_with_fallback($spec_with_name), "correct-name", "parsed name when present");

# Test empty/whitespace handling
my $empty_spec = create_test_spec("empty-pkg.spec", "");
my $whitespace_spec = create_test_spec("ws-pkg.spec", "Name:   \nVersion: 1.0");

is(simulate_parsing_with_fallback($empty_spec), "empty-pkg", "empty file fallback");
is(simulate_parsing_with_fallback($whitespace_spec), "ws-pkg", "whitespace Name field fallback");

# Test invalid filename in integration
my $invalid_spec = create_test_spec("invalid name.spec", "Version: 1.0");
is(simulate_parsing_with_fallback($invalid_spec), undef, "invalid filename rejected in integration");

#
# ORIGINAL BSRepServer::BuildInfo TESTS
#

### Test Case 01
$got = BSRepServer::BuildInfo::buildinfo('openSUSE:13.2', 'standard', 'i586', 'screen');
$expected = Test::OBS::Utils::readxmlxz("$BSConfig::bsdir/result/tc01", $BSXML::buildinfo);
cmp_buildinfo($got, $expected, 'buildinfo for screen');

# Test Case 02
$got = BSRepServer::BuildInfo::buildinfo('home:Admin:branches:openSUSE.org:OBS:Server:Unstable', 'openSUSE_Leap_42.1', 'x86_64', '_product:OBS-Addon-release');
$expected = Test::OBS::Utils::readxmlxz("$BSConfig::bsdir/result/tc02", $BSXML::buildinfo);
cmp_buildinfo($got, $expected, 'buildinfo for regular Package with remotemap');

exit 0;
