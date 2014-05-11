#!/usr/bin/perl
#use warnings;
#use strict;

# Points the BCB, an area at the end of an SD card, at the bootstream image
# that will live at the start of the card.
# Note that the image must be encrypted.
#
# This can be most useful when testing unblown boards.  Be sure to pass the
# -z bootstream parameter when building the image to be written, as by
# default boards won't boot unsigned images.

my $dev;

# Grab the device we're going to write to.
defined($ARGV[0]) || die("Usage: $0 <device> (e.g. $0 /dev/sde)\n");

$dev  = $ARGV[0];

# Attempt to open the device and the file.
open(my $d_fh, '<', $dev) or die("Couldn't open device $dev: $!");




# Scan for the STMP signature, which is at the block's start offset + 20 bytes.
my $st1;
print STDERR "Locating boot signature...";
#zhai changed --- for(my $offset=0; $offset<1024 && !defined($st1); $offset++) {
for(my $offset=0; $offset<4096 && !defined($st1); $offset++) {

    # Seek to $offset blocks, and add 20.
    seek($d_fh, (512*$offset)+20, 0);

    my $test_data;
    read($d_fh, $test_data, 4);
    if($test_data eq 'STMP') {
        print STDERR " block $offset\n";
        $st1 = $offset;
    }
}
if(!defined($st1)) {
    print STDERR " fatal: couldn't find boot signature on $file\n";
    exit(1);
}


# Seek to the very last block.
print STDERR "Determining last block...";
seek($d_fh, 0, 0);
seek($d_fh, -512, 2);
my $d_end = tell($d_fh);

# If $d_end is false (as happens on, for example, OS X), find the end via a
# brute-force method.
if(0 == $d_end) {
    print STDERR " (brute-force method) ";
    my $offset = 0;
    my $bytes;

    # First pass: Increment in 4096-blocks of 512 bytes, just to get a rough
    # gauge.
    while(read($d_fh, $bytes, 1)) {
        $offset+=4096;
        seek($d_fh, $offset*512, 0);
    }
    $offset -= 4096;
    seek($d_fh, $offset*512, 0);

    # Now, go in 1-block 512-byte chunks to get an exact offset.
    while(read($d_fh, $bytes, 1)) {
        $offset++;
        seek($d_fh, $offset*512, 0);
    }

    # Subtract 512 bytes so that $offset points at the last block.
    $offset--;

    $d_end = $offset;
}
else {
    $d_end /= 512;
}
print STDERR " block $d_end\n";



# Reopen the device as write-only.
close($d_fh);
open($d_fh, '+>', $dev) or die("Couldn't open device $dev: $!");

# Seek to the correct offset for where we'll put the bootstream data.
seek($d_fh, ($d_end-2)*512, 0);


# Write the boot information.
my $bytes = pack("VNNNVVNNNN", 0x00112233, 0x01000000,
                               0x02000000, 0x50000000,
                               $st1,       $st1,
                               0x50000000, 0x50000000,
                               0x50000000, 0x50000000);

print STDERR "Writing boot block starting at offset " . ($d_end-2)*512 . "...";

for(1..4) {
    print $d_fh $bytes;

    # Fill out the rest of the sector.
    my $bytes_left = 512-length($bytes);
    for(1..$bytes_left) {
        print $d_fh chr(0x00);
    }
}

print STDERR " done.\n";

close($d_fh);
