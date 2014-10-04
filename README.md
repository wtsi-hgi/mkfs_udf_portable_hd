mkfs_udf_portable_hd
====================

Formats and partitions a portable hard drive with the UDF filesystem, 
for use as a portable drive that can be accessed from Linux, Mac, and 
Windows systems. 

This script may be useful to you if you have a need for a portable 
hard drive that can be accessed from multiple platforms and supports 
large files (FAT32 works well but has a maximum 4GB file size). It 
now supports newer portable hard drives with 4096 bytes per physical 
sector. 

`mkfs_udf_portable_hd.pl` requires either the `mkudffs` (Linux) or 
`newfs_udf` (BSD / Darwin / Mac OS X) utility to actually create 
the filesystem. On Ubuntu Linux, this is provided by the `udftools` 
package. 

This work is based on the `udfhd.pl` [script] [1]  by Pieter Wuille. 
For more information on why this script is needed, please refer to 
his [excellent blog post] [2] on the topic.



Copyright note
--------------

The usage of a range of years within a copyright statement contained within 
this distribution should be interpreted as being equivalent to a list of years 
including the first and last year specified and all consecutive years between 
them. For example, a copyright statement that reads `Copyright (c) 2005, 2007-
2009, 2011-2012' should be interpreted as being identical to a statement that 
reads `Copyright (c) 2005, 2007, 2008, 2009, 2011, 2012' and a copyright 
statement that reads `Copyright (c) 2005-2012' should be interpreted as being 
identical to a statement that reads `Copyright (c) 2005, 2006, 2007, 2008, 
2009, 2010, 2011, 2012'." 

[1]: http://sipa.ulyssis.org/software/scripts/udf-harddisk/
[2]: http://sipa.ulyssis.org/2010/02/filesystems-for-portable-disks/
