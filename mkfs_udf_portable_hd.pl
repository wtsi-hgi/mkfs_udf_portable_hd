#!/usr/bin/env perl
#    mkfs_udf_portable_hd.pl - partition and format a hard disk using UDF
#    accessible by Linux, Mac, and Windows systems
#
#    Copyright (c) 2014 Genome Research Ltd.
#
#    based on udfhd.pl by Pieter Wuille
#    Copyright (C) 2010   Pieter Wuille
#
#    Authors: 
#      Pieter Wuille
#      Joshua C. Randall <jcrandall@alum.mit.edu>
#
#    This program is free software: you can redistribute it and/or modify
#    it under the terms of the GNU General Public License as published by
#    the Free Software Foundation, either version 3 of the License, or
#    (at your option) any later version.
#
#    This program is distributed in the hope that it will be useful,
#    but WITHOUT ANY WARRANTY; without even the implied warranty of
#    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#    GNU General Public License for more details.
#
#    You should have received a copy of the GNU General Public License
#    along with this program.  If not, see <http://www.gnu.org/licenses/>.

use strict;
use warnings;
use Fcntl qw(SEEK_SET SEEK_END);

my $PART_TYPE = 0x0B;

sub encode_lba {
    my ($lba) = @_;
    my $res = pack("V", $lba);
    return $res;
}

sub encode_chs {
    my ($lba, $heads, $sects) = @_;
    my $C = $lba / ($heads * $sects);
    if ($C > 1023) {
	$C = 1023;
    }
    my $S = 1 + ($lba % $sects);
    my $H = ($lba / $sects) % $heads;
    my $res = pack("CCC", $H & 255, (($S & 63) | ((($C / 256) & 3) * 64)), $C & 255);
    return $res;
}

sub encode_entry {
    my ($begin_sect, $size_sect, $bootable, $type, $heads, $sects) = @_;
    if ($size_sect == 0) {
	return (pack("C", 0) x 16);
    }
    my $res = "";
    if ($bootable) { 
	$res = pack("C", 0x80); 
    } else { 
	$res = pack("C", 0); 
    }
    $res .= encode_chs($begin_sect, $heads, $sects);
    $res .= pack("C", $type);
    $res .= encode_chs($begin_sect+$size_sect-1, $heads, $sects);
    $res .= encode_lba($begin_sect);
    $res .= encode_lba($size_sect);
    return $res;
}

sub generate_fmbr {
    use integer;
    my ($maxlba, $heads, $sects, $type) = @_;
    $maxlba -= ($maxlba % ($heads * $sects));
    my $res = pack("C", 0) x 440; # code section
    $res .= pack("V", 0);       # disk signature
    $res .= pack("C", 0) x 2;   # padding
    $res .= encode_entry(0, $maxlba, 0, $type, $heads, $sects); # primary partition spanning whole disk
    $res .= pack("C", 0) x 48;  # 3 unused partition entries
    $res .= pack("C", 0x55);    # signature part 1
    $res .= pack("C", 0xAA);    # signature part 2
    return ($res, $maxlba);
}

# autoflush STDOUT
$ |= 1;

if (! -e $ARGV[0]) {
    print "Syntax: $0 /dev/diskdevice [label] [size_in_bytes]\n"
}

my $udfpath = "";
my $udftype;
if (-x "/usr/bin/mkudffs") { 
    $udfpath = "/usr/bin/mkudffs"; 
    $udftype = "mkudffs";
}
if (-x "/sbin/newfs_udf") { 
    $udfpath = "/sbin/newfs_udf"; 
    $udftype = "newfs_udf";
}

if (! defined($udftype)) {
    die "Neither mkudffs or newfs_udf could be found.\n";
}

my $dev = shift @ARGV;
my $label = shift @ARGV || "UDF";

die "device $dev does not exist!\n" unless (-e $dev);
die "device $dev not a block device!\n" unless (-b $dev);
die "device $dev not readable\n" unless (-r $dev);
die "device $dev not writeable (perhaps try sudo?)\n" unless (-w $dev);

# default sector size is 512 unless we know otherwise
my $sector_size = 512;

# try getting size with -s
my $size = (-s $dev);

# if size was specified as argument, set it
if (defined $ARGV[0]) {
    $size = shift @ARGV;
}

# TODO: get sector_size argument

# if we have diskutil, use it to get block size and disk size
if (-x "/usr/sbin/diskutil") {
    my $diskutil_info = `/usr/sbin/diskutil info $dev`;
    if ($diskutil_info =~ m/\s*Device\s+Block\s+Size:\s+([0-9]+)\s+Bytes/) {
	$sector_size = $1;
    }
    if ($diskutil_info =~ m/\s*Total\s+Size:.*?([0-9]+)\s+Bytes/) {
	$size = $1;
    }
}

# TODO: add lshw check

# open disk device or die
open(DISK, "+<", $dev) || die "Cannot open '$dev' read/write: $!\n";

# if we don't have size yet, try determining with sysseek
if ($size <= 0) {
    $size = sysseek(DISK, 0, SEEK_END);
    sysseek(DISK, 0, SEEK_SET);
}

# if we don't have size yet, try determining with seek/tell
if ($size <= 0) {
    seek(DISK, 0, SEEK_END) || die "Cannot seek to end of device: $!\n";
    $size = tell(DISK);
}
seek(DISK, 0, SEEK_SET) || die "Cannot seek to begin of device: $!\n";

# if we still don't have size, try one last time with -s
if ($size <= 0) {
    $size = (-s $dev);
} 

# give up if we don't have size
die "Cannot find device size, please use: $0 device label [size_in_bytes]\n" unless ($size > 0);

print "Writing MBR...";
my ($mbr, $maxlba) = generate_fmbr($size/$sector_size, 255, 63, $PART_TYPE);
print DISK $mbr || die "Cannot write MBR: $!\n";
print "done!\n";

print "Cleaning first 4096 sectors...";
for (my $i=1; $i < 4096; $i++) {
    print DISK (pack("C",0) x $sector_size) || die "Cannot clear sector $i: $!\n";
}
print "done!\n";

close(DISK) || die "Cannot close disk device: $!\n";

print "Creating $maxlba-sector UDF v2.01 filesystem with label '$label' on $dev using $udftype...\n";
if ($udftype eq "mkudffs") {
    system($udfpath, "--blocksize=$sector_size", "--udfrev=0x0201", "--lvid=$label", "--vid=$label", "--media-type=hd", "--utf8", $dev, $maxlba);
} elsif ($udftype eq "newfs_udf") {
    system($udfpath, "-b", $sector_size, "-m", "blk", "-t", "ow", "-s", $maxlba, "-r", "2.01", "-v", $label, "--enc", "utf8", $dev);
}
