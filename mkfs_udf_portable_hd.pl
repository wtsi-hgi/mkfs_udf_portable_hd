#!/usr/bin/env perl
#
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
use Getopt::Long;
use Pod::Usage;

# option defaults
my $part_type = 0x0B;
my $label = "UDF";
my $size = 0;
my $sector_size = 512;
my $man = 0;
my $help = 0;

# get command-line options
my $result = GetOptions(
    "part_type=s"   => \$part_type,
    "label=s"       => \$label,
    "size=i"        => \$size,
    "sector_size=i" => \$sector_size,
    "help|?"        => \$man,
    ) or pod2usage(2);

pod2usage(1) if $help;
pos2usage(-exitval => 0, -verbose => 2) if $man;

# get command-line argument
my $dev = shift @ARGV || pod2usage(2);

# Encode a Logical Block Address (LBA) 
sub encode_lba {
    my ($lba) = @_;
    my $res = pack("V", $lba);
    return $res;
}

# Encode Cylinder-Head-Sector (CHS)
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

# Encode a partition-table entry
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

# Generate Master Boot Record (MBR) for disk
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

# determine which tool to use (mkudffs on Linux, newfs_udf on Mac)
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

die "device $dev does not exist!\n" unless (-e $dev);
die "device $dev not a block device!\n" unless (-b $dev);
die "device $dev not readable\n" unless (-r $dev);
die "device $dev not writeable (perhaps try sudo?)\n" unless (-w $dev);

if (-x "/usr/sbin/diskutil") {
    # if we have diskutil, use it to get block size and disk size
    my $diskutil_info = `/usr/sbin/diskutil info $dev`;
    if ($diskutil_info =~ m/\s*Device\s+Block\s+Size:\s+([0-9]+)\s+Bytes/) {
	$sector_size = $1;
    }
    if ($diskutil_info =~ m/\s*Total\s+Size:.*?([0-9]+)\s+Bytes/) {
	$size = $1;
    }
} elsif (-e "/sys/block") {
    # if we are on linux, get information from /sys/block
    my $blockdir = $dev;
    $blockdir =~ s/.*\///;
    my $pbs_file = "/sys/block/$blockdir/queue/physical_block_size";
    my $size_file = "/sys/block/$blockdir/size";
    if (-e $pbs_file) {
	open(PBSFILE, "<", $pbs_file) or die "cannot open $pbs_file for reading\n";
	$sector_size = <PBSFILE>;
	chomp $sector_size;
	close(PBSFILE);
    }
    if (-e $size_file) {
	open(SIZEFILE, "<", $size_file) or die "cannot open $size_file for reading\n";
	my $sectors = <SIZEFILE>;
	chomp $sectors;
	$size = $sectors * 512; # /sys/block/*/size always returns size in count of 512-byte sectors
	close(SIZEFILE);
    }
} else {
    # assume default sector_size and try to determine disk size empirically

    # try getting size with -s
    $size = (-s $dev);
    
    # if we don't have nonzero size yet, try determining with sysseek
    if ($size <= 0) {
	use Fcntl qw(SEEK_SET SEEK_END);
	open(DISK, "<", $dev) || die "Cannot open '$dev' for reading: $!\n";
	$size = sysseek(DISK, 0, SEEK_END);
	sysseek(DISK, 0, SEEK_SET);
    }
    
    # if we don't have nonzero size yet, try determining with seek/tell
    if ($size <= 0) {
	seek(DISK, 0, SEEK_END) || die "Cannot seek to end of device: $!\n";
	$size = tell(DISK);
    }
    close(DISK) || die "Cannot close device: $!\n";
    
    # if we still don't have nonzero size, try one last time with -s
    if ($size <= 0) {
	$size = (-s $dev);
    } 
    
    # give up if we don't have nonzero size
    die "Cannot find device size, please use: $0 device label [size_in_bytes]\n" unless ($size > 0);
}

# autoflush STDOUT
$ |= 1;

# open disk device R/W or die
open(DISK, "+<", $dev) || die "Cannot open '$dev' read/write: $!\n";

print "Writing MBR...";
my ($mbr, $maxlba) = generate_fmbr($size/$sector_size, 255, 63, $part_type);
print DISK $mbr || die "Cannot write MBR: $!\n";
print "done!\n";

print "Cleaning first 4096 sectors...";
for (my $i=1; $i < 4096; $i++) {
    print DISK (pack("C",0) x $sector_size) || die "Cannot clear sector $i: $!\n";
    if ($i % 128 == 0) {
	print ".";
    }
}
print "done!\n";

close(DISK) || die "Cannot close disk device: $!\n";

my @udfargs; 
if ($udftype eq "mkudffs") {
    @udfargs = ($udfpath, "--blocksize=$sector_size", "--udfrev=0x0201", "--lvid=$label", "--vid=$label", "--media-type=hd", "--utf8", $dev, $maxlba);
} elsif ($udftype eq "newfs_udf") {
    @udfargs = ($udfpath, "-b", $sector_size, "-m", "blk", "-t", "ow", "-s", $maxlba, "-r", "2.01", "-v", $label, "--enc", "utf8", $dev);
}

print "Calling $udftype...";
system(@udfargs) == 0 or die "$udftype failed: $?\n";
print "done!\n";

print "Created $maxlba-sector UDF v2.01 filesystem with label '$label' on $dev with $sector_size bytes per sector (total $size bytes).\n";
