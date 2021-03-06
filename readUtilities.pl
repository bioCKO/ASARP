#!/usr/bin/perl
use warnings;
use strict;

our $INTRVL = 100000; #interval to output processed counts

# all sub-routine utilities here
# for processing reads and pipe-ups

# mask for certain read positions (with low qualities)
# input:	a position list (one-based start and end, inclusive)
# output:	an array with the masked positions marked 1, and others 0's
# NOTE: the position list is a comma separated list, where each element is in a range form: "a:b"
# indicating read position range from a to b (one-based, inclusive) is discarded
# For the special case of "a:a", one can simply write "a" in the comma list as the element
# For example, 1,4:6,100 is equivalent to 1:1,4:6,100:100
# **IMPORTANT NOTE**: the return mask array is for INTERNAL use, and the positions are converted to **zero-based** ones.
sub readPosMask
{
  my ($discardPos) = @_;
  my @discard = ();

  #print "discard: $discardPos\n";
  print "Evaluating syntax of discarded read positions (one-based, range start-end inclusive)...\n";
  my $previousTo = 0;
  my @poss = split(',', $discardPos);
  for(@poss){
    my ($from, $to, $extra) = split(':', $_);
    if(defined($extra)){
      print "\nERROR: each range only allows one ':': $_\n";
      exit;
    }
    if(!defined($to)){
      $to = $from;
    }
    if(!($from=~/\d+/) || !($to=~/\d+/)){
      print "\nERROR: cannot pass $from or $to as integers\n";
      exit;
    }
    if($previousTo > $from || $from > $to){
      print "\nERROR: discarded read positions/ranges must be sorted: ..:$previousTo,$from:$to\n";
      exit;
    }
    print "$from:$to,";
    for(my $i=$from-1; $i<=$to-1; $i++){ #zero-based internally
      $discard[$i] = 1; #fill-in discarded positions
    }
    $previousTo = $to;
  }
  if($previousTo>0){
    print "\n";
  }
  for(my $i = 0; $i< $previousTo; $i++){
    if(!defined($discard[$i])){	$discard[$i] = 0; }
  }

  return @discard;

}

# read in the raw DNA SNV List
sub readSnvList
{
  my ($snvFile, $chrToCheck) = @_;
  my $INTRVL = 100000;
  my $snvList = "";
  my ($dSnvCnt, $cSnvCnt) = (0, 0);
  open(SNP, "<", $snvFile) or die "ERROR: Can't open $snvFile\n";
  while(<SNP>){
    chomp;
    ++$dSnvCnt;
    if($dSnvCnt%$INTRVL == 0){ print "$dSnvCnt...";  }
    my ($chr, $pos, $alleles, $id) = split(' ', $_);
    if($chr ne $chrToCheck){
      next; #ignore all other chromosomes to save time
    }
    my $str = join(" ", $pos, $alleles, $id);
    if($snvList ne ""){
      $snvList .= "\t".$str;
    }else{  $snvList = $str;	}
    ++$cSnvCnt;
  }
  close(SNP);
  print " $cSnvCnt SNVs read for $chrToCheck out of $dSnvCnt. Done.\n";
  return $snvList; # or the string
}

# convert the dnaSnvList (a string) into the hash
sub procDnaSnv{

  my ($snvList, $chr) = @_;
  ####################################################################
  
  print "Processing $chr genomic SNVs...";
  my @dnaSnvVals = split('\t', $$snvList);
  my %dnaSnvs = ();
  for(@dnaSnvVals){
    my ($pos, $als, $id) = split(' ', $_);
    $dnaSnvs{$pos} = $als." ".$id;
  }
  my @dnaSnvs_idx = sort{$a <=> $b} keys %dnaSnvs;
  my $dnaSnvNo = keys %dnaSnvs;
  print " $dnaSnvNo SNVs. Done.\n";
  return (\%dnaSnvs, \@dnaSnvs_idx);
}


# get the pair strand (using pair 1 information and strand flag in the setting)
sub getStrandInRead{
  # handle the strand info according to SAM format: http://samtools.sourceforge.net/SAM1.pdf
  my ($strand, $strandFlag) = @_; 
  if($strand & 4){ # 0x4
    die "ERROR: only mapped reads are accepted; please filter unmapped (0x4) reads using other tools\nException flag: $strand\n";
  }
  #if($strand & 256){ # 0x100
  #  die "ERROR: only uniquely mapped reads are accepted; please filter unmapped (0x4) reads using other tools\nException flag: $strand\n";
  #}
  if($strand & 16){ # i.e. 0x10 
    $strand = '-'; #antisense
    if($strandFlag == 2){ # pair 1 is anti-sense
      $strand = '+'; #flip pair 1's strand
    }
  }else{
    $strand = '+'; 
    if($strandFlag == 2){ # pair 1 is anti-sense
      $strand = '-'; #flip pair 1's strand
    }
  }
  return $strand;
}  

sub checkPairChr
{
  my ($chr1, $chr2, $line) = @_;
  if($chr1 ne $chr2){
    #die "ERROR: reads have to be in pairs in the same chromosome: $id in $chr different from $id2 in $chr2 at line $cnt\n";
    die "ERROR: $chr1 != $chr2 in line $line\n"; 
  }
}

sub checkPairId
{
  my ($id1, $id2, $cnt) = @_; 
  # add back the check for id1 and id2: they should be identical or differ only with the last 2 characters, typically: /1 and /2
  if($id1 ne $id2){
        my $idLen = length($id1)-2; # ignoring the last 2 characters
        my $id1p = substr($id1, 0, $idLen);
	my $id2p = substr($id2, 0, $idLen);
	if($id1p ne $id2p){
	  die "ERROR: reads have to be in pairs: $id1 differs from $id2 by more than the last 2 characters in line $cnt\n";
	}
      
  }
}

sub mergeBlockInPair
{
  my ($bk1, $bk2, $start2) = @_;
  my @blocks1 = split(',', $bk1); # blocks for pair 1
  my @blocks2 = split(',', $bk2);
  my $output = "";
  my $output2 = "";
  my ($lastStart1, $end1) = split(':', $blocks1[-1]); # last block
  my $isOverlap = 0;
  if($end1 < $start2){
    if($bk1 ne ''){	$output .= $bk1;	}
    if($bk2 ne ''){	$output .= ",$bk2";	}
    return ($output, $isOverlap);
  }else{ # get the overlap part and return them
    $isOverlap = 1;
    #print "\noverlap: $bk1; $bk2\n";
    my ($offset) = split(':', $blocks1[0]); # the smallest offset
    my ($lastStart2, $end) = split(':', $blocks2[-1]); # the final end
    if($offset > $start2){ $offset = $start2; }
    if($end < $end1){ $end = $end1; }

    my @bIndi = (); # block position indicator
    for(my $j=0; $j<$end-$offset+1; $j++){
      $bIndi[$j] = 0;
    }
    my $len = @bIndi;
    for(@blocks1){
      my ($s, $e) = split(':', $_);
      for($s..$e){  $bIndi[$_-$offset] = 1; }
    }
    for(@blocks2){
      my ($s, $e) = split(':', $_);
      for($s..$e){  $bIndi[$_-$offset] = 1; }
    }
    my ($f, $start) = (0, 0); #flag
    for(my $j=0; $j<@bIndi; $j++){
      if(!$f){
        if($bIndi[$j]){
          $f = 1;
	  $start = $j+$offset;
	}
      }else{
        if(!$bIndi[$j]){
	  my $bkEnd = $j-1+$offset;
	  #ready to output
	  if($output2 ne ''){
	    $output2 .= ",$start:$bkEnd";
	  }else{ $output2 = "$start:$bkEnd"; }
	  $f = 0; # unseet flag
	}
      }
    }
    if($f){
      my $bkEnd = @bIndi+$offset-1;
      if($output2 ne ''){
        $output2 .= ",$start:$bkEnd";
      }else{ $output2 = "$start:$bkEnd"; }
    }

    #print "merged: $output2\n";
  }
  return ($output2, $isOverlap);
}

# simply process the block (which may contain sub-blocks) into the blocks hash
# input:	the block to be merged
# output:	reference to the hash of blocks
# output:	reference to the index array of the block starts
sub procBlocks{
  my ($block) = @_; 
  my %allBlocks = ();
  my @blks = split(',', $$block);
  for(@blks){
    if($_ ne ''){
      my ($blkS, $blkE) = split(':', $_);
      if(defined($allBlocks{$blkS})){
        $allBlocks{$blkS} .= "\t".$blkE;
      }else{
        $allBlocks{$blkS} = $blkE;
      }
    }
  }
  my @blkStarts = sort{$a<=>$b} keys %allBlocks;
  return (\%allBlocks, \@blkStarts);
}

# mask (i.e. eliminate some parts of) the blocks according to the read position mask
# Assumption: the block lengths should add up to the read length (i.e. no in-dels)
# input:	a block in its original string form in the sam file ("a:b,c:d...")
# input:	the reference to the position mask
# output:	masked block in its string form ("a:b,c:d...")
sub maskBlock{
  my ($block, $readLen, $maskRef) = @_;
  my @mask = @$maskRef;
  my $ttlBlkLen = 0; #for checking in-dels
  #print "maskBlock\norg: $block\n";
  my @blks = split(',', $block);
  my @newBlks = ();
  my $readOffset = 0;
  for(@blks){
    my ($s, $e) = split(':', $_);
    my $len = $e-$s+1;
    #print "analyzing $s:$e, len $len\n";
    $ttlBlkLen += $len;
    my $ts = $s; #temp start for broken blocks
    my $i = 0;
    for($i = 0; $i+$readOffset < @mask && $i<$len; $i++){
      if($mask[$i+$readOffset]){ # break point appears
        my $break = $s+$i;
        #print "break at $break (pos $i+$readOffset)\n"; 
        #check if it is a non-empty sub-block
        if($ts <= $break-1){
          push(@newBlks, $ts.":".($break-1));
        }
        #set the next s, so the skipped position is exactly $break
        $ts = $break+1;
      }
    }
    # have to handle the left-overs
    if($ts<=$e){ #there are left-overs
      push(@newBlks, $ts.":".$e);
    }
    $readOffset += $len; #this block is over
  }
  #print "new: ", join(',', @newBlks), "\n";
  #print "Read len: $ttlBlkLen\n";
  if($ttlBlkLen != $readLen){ die "ERROR: wrong total block length: $ttlBlkLen (read length $readLen)\n"; }
  return join(',', @newBlks);
}

# process bedgraph (non-strand specific)
# input:	the references to the blocks and their indices
# output:	the references to the begraph and its index 
sub procBeds{

  my ($blkRef, $blkStarts, $chr) = @_;

  my %thisChrBlks = %$blkRef;
  my $blkNo = @{$blkStarts};
  print " $blkNo block starts. Done.\n";

  #print "Processing $chr bedgraph...";
  my @bedgraph = (); #bedgraph content in increasing order
  my @bedgraph_idx = (); #sorted index array of the bedgraph

  my $left4Next = ""; #those parts running into the next block
  for(my $i=0; $i<$blkNo; $i++){
    my $thisStart = $$blkStarts[$i];
    my $nextStart = -1;
    if($i<$blkNo-1){ #if not the last one, there still a next start
      $nextStart = $$blkStarts[$i+1]; 
    }
    # get the previous left-overs
    if($left4Next ne ""){
      $thisChrBlks{$thisStart} .= "\t".$left4Next;
      # $left4Next can be cleared up to here
      $left4Next = "";
    }
    my @thisEnds = split("\t", $thisChrBlks{$thisStart});
    @thisEnds = sort{$a<=>$b} @thisEnds; #sort all the ends

    my $pileupNo = @thisEnds;
    my $s = $thisStart-1; #make it zero-based to be consistent with bedgraph
    for(my $j = 0; $j < $pileupNo; $j++){
      #$nextStart == -1 means the last block, and i need to handle it without left-overs
      if($nextStart != -1 && $thisEnds[$j] >= $nextStart){ # i won't do it
        # dump left-overs to the next guy whenever possible
	if($left4Next eq ""){
	  $left4Next = $thisEnds[$j];
	}else{
          $left4Next .= "\t".$thisEnds[$j];
	}
	$thisEnds[$j] = $nextStart-1; # i will handle up to here
      } 

      #ok, it's my responsibiity to handle it
      if($s == $thisEnds[$j]){
        next; #i.e. there are two blks with the same ends, and it's already counted
      }
      #if the first pileup is an extension to the previous one: prv end = this start, counts equal
      if($j == 0 && @bedgraph>0){
        #extendable from the previous
	my ($pChr, $pS, $pE, $pCnt) = split(' ', $bedgraph[-1]); #chr start end count
	if($pE == $s && $pCnt == $pileupNo){
	  pop @bedgraph; #need to update the previous one
	  pop @bedgraph_idx; #idex needs the pop as well
	  $s = $pS; #extend the start (use the previous one)
	}
      }
      #the start needs to be zero-based
      push(@bedgraph, "$chr $s $thisEnds[$j] ".($pileupNo-$j));
      push(@bedgraph_idx, $s); #the start as the index
      $s = $thisEnds[$j]; # the next start converted to zero-based: +1 then -1
    }
  }

  return (\@bedgraph, \@bedgraph_idx);

}

sub procBedgraph{
  my ($chr, $blocksRef) = @_;

  print "Processing $chr mapped blocks and bedgraph...\n";
  my ($blkRef, $blkIdxRef) = procBlocks($blocksRef);
  my ($bedRef, $bedIdxRef) = procBeds($blkRef, $blkIdxRef, $chr);
  return ($bedRef, $bedIdxRef);
}

sub outputBedgraph{

  my ($chr, $outputBedgraph, $title, $strandFlag, $bedRef, $bedIdxRef, $bedRcRef, $bedRcIdxRef) = @_;
  my @bedgraph = @$bedRef;
  my @bedgraph_idx = @$bedIdxRef;
  my @bedgraphRc = (); if(defined($bedRcRef)){ @bedgraphRc =  @$bedRcRef; }
  my @bedgraphRc_idx = (); if(defined($bedRcIdxRef)){ @bedgraphRc_idx =  @$bedRcIdxRef; }


  ####################################################################
  # output bedgraph
  open(BP, ">", $outputBedgraph) or die "ERROR: cannot open $outputBedgraph to output bedgraph\n";
  # output bedgraph for this chromosome
  my $addDescr = "$title; ";
  # get the track opt first
  my $bedFirstPos = -1;
  my $bedLastPos = 0;
  if(@bedgraph_idx > 0){ # extra check for exceptions
  (my $dummyChr, my $dummyS, $bedLastPos) = split(" ", $bedgraph[-1]);
  $bedFirstPos = $bedgraph_idx[0];
  if($strandFlag){
    $addDescr .= "strand-specific: the extra field is strand";
    if(@bedgraphRc > 0){ # extra check for exceptions
    my ($dummyChr2, $dummyS2, $bedLastPos2) = split(" ", $bedgraphRc[-1]);
    if(defined($bedLastPos2) && $bedLastPos2 > $bedLastPos ){
      $bedLastPos = $bedLastPos2;
    }
    if($bedgraphRc_idx[0] < $bedFirstPos){
      $bedFirstPos = $bedgraphRc_idx[0];
    }
    }
  }
  }
  my $trackRange = "$chr:".($bedFirstPos+1).":".$bedLastPos; #start converted back to 1-based for chr range in UCSC
  my $trackOpt = "track type=bedGraph name=\"reads_$chr\" description=\"$trackRange $addDescr\" visibility=full autoScale=on gridDefault=on graphType=bar yLineOnOff=on yLineMark=0 smoothingWindow=off alwaysZero=on\n";
  print BP $trackOpt;
  my $bedCnt = 0;
  print "Outputting bedgraph file...";
  if($strandFlag){
    print "\nstrand-specific set: + and - attributes are output in the bedgraph...\n";
    print "+\n";
    for(@bedgraph){
      print BP $_." +\n"; #strand added
      $bedCnt++;
      if($bedCnt%$INTRVL == 0){ print "$bedCnt...";  }
    }
    print "-\n";
    for(@bedgraphRc){
      print BP $_." -\n"; #strand added
      $bedCnt++;
      if($bedCnt%$INTRVL == 0){ print "$bedCnt...";  }
    }

  }else{ # non-strand specific
    for(@bedgraph){
      print BP $_."\n";
      $bedCnt++;
      if($bedCnt%$INTRVL == 0){ print "$bedCnt...";  }
    }
  }
  close(BP);
  print " $bedCnt lines. Done.\n";

  if($strandFlag){
    my @bedgraphRc = @$bedRcRef;
    my @bedgraphRc_idx = @$bedRcIdxRef;
    print "Outputting standard 4-attribute bedgraph files ($outputBedgraph.plus and .minus), one for each strand...";
    open(PP, ">", "$outputBedgraph.plus") or die "ERROR: cannot open $outputBedgraph.plus to output bedgraph\n";
    my ($bpp1, $bpp2) = (0, 1); 
    if(@bedgraph_idx >0){
      $bpp1 = $bedgraph_idx[0];
      my ($dummyChr, $dummyS, $bedLastPos) = split(" ", $bedgraph[-1]);
      $bpp2 = $bedLastPos;
    } 
    my $plusRange = "$chr:".($bpp1+1).":".$bpp2; #start converted back to 1-based for chr range in UCSC
    print PP "track type=bedGraph name=\"reads_".$chr."_plus\" description=\"$plusRange $title; + strand only\" visibility=full autoScale=on gridDefault=on graphType=bar yLineOnOff=on yLineMark=0 smoothingWindow=off alwaysZero=on\n";
    for(@bedgraph){
      print PP $_."\n"; #strand added
    }
    close(PP);
    
    
    open(MP, ">", "$outputBedgraph.minus") or die "ERROR: cannot open $outputBedgraph.minus to output bedgraph\n";
    my ($bmp1, $bmp2) = (0, 1); 
    if(@bedgraphRc_idx >0){
      $bmp1 = $bedgraphRc_idx[0];
      my ($dummyChr2, $dummyS2, $bedLastPos2) = split(" ", $bedgraphRc[-1]);
      $bmp2 = $bedLastPos2;
    } 
    my $minusRange = "$chr:".($bmp1+1).":".$bmp2; #start converted back to 1-based for chr range in UCSC
    print MP "track type=bedGraph name=\"reads_".$chr."_minus\" description=\"$minusRange $title; - strand only\" visibility=full autoScale=on gridDefault=on graphType=bar yLineOnOff=on yLineMark=0 smoothingWindow=off alwaysZero=on\n";
    for(@bedgraphRc){
      print MP $_."\n"; #strand added
    }
    close(MP);
    print " ".(scalar @bedgraph)." + lines and ".(scalar @bedgraphRc)." - lines. Done. \n";

  }

}


# parse the CIGAR string to get block information
sub parseCigar{
  my ($start, $cigar) = @_;
  my $position = $start;
  my $block = '';
  while ($cigar !~ /^$/){
    # handle only the matched parts
    if ($cigar =~ /^([0-9]+[MIDSN])/){
      my $cigar_part = $1;
      if ($cigar_part =~ /(\d+)M/){
        if($block ne ''){ #already some blocks
	  $block .= ",";
	}
	$block .= "$position:";
        $position += $1;
	my $end = $position - 1;
	$block .= "$end";
      } elsif ($cigar_part =~ /(\d+)N/){
        $position += $1; # skipped positions
      } else { 
	print STDERR "WARNING: CIGAR not supported: $cigar\n"; 
        return undef; 
      }
      #} elsif ($cigar_part =~ /(\d+)I/){
      #} elsif ($cigar_part =~ /(\d+)D/){
      #} elsif ($cigar_part =~ /(\d+)S/){
      $cigar =~ s/$cigar_part//;
    }else{
      print STDERR "WARNING: CIGAR not supported: $cigar\n"; 
      return undef; 
      #die "ERROR: CIGAR type not yet supported: $cigar\n";
    }
  }
  return $block;
}

##
# merge SNVs of different chromosomes into one SNV list
# the equivalent can be achieved using cat and grep commands
# for strand-specific cases '+$' and '\-$' can get all SNVs from the
# + and - strands respectively
# USAGE perl $0 prefix suffix output [isSS]
# prefix	the folder path and prefix string for all chr* SNV files
# 		e.g. "/home/N.A+/" for all chr* SNVs in that folder
# suffix	the suffix after chr[1..22/X/Y/M]
# output	the output file name for the merged SNVs
# 		note that output.plus and output.minus are by-product
# 		outputs for + and - strands for strand-specific cases
# 		make sure the output and chr* SNV file names do not conflict
# OPTIONAL
# isStrand	set 1 if the SNV files are strand-specific
sub mergeSnvs
{
  my ($prefix, $suffix, $isMono, $output, $isStranded) = @_;
  my $cmd = "cat $prefix"."chr*$suffix";
  my $cmdO = ""; # output command
 
  # add allelic ratios, coverage for histogram and scatter plots
  my @rto = (); # allelic ratios
  my @cov = (); # coverage
  # add total ref and alt read counts for the binomial test
  my ($refcnt, $altcnt) = (0, 0);
  if(defined($isStranded) && $isStranded == 1){
    my $cmdP = "$cmd | grep '+\$' >$output.plus ";
    my $cmdM = "$cmd | grep '\\-\$' >$output.minus ";
    print "Handling + and - SNVs:\n$cmdP\n$cmdM\n";
    system($cmdP) == 0 or print "$cmdP failed\n";
    system($cmdM) == 0 or print "$cmdM failed\n";
    $cmdO = "cat $output.plus $output.minus > $output";
  }else{
    $cmdO = "$cmd > $output";
  }
  print "Outputting merged SNVs to $output\n";
  system($cmdO) == 0 or die "$cmdO failed\n";

  if(1){ #$isMono){
    my ($n, $x) = (0, 0);
    if($isMono){
      print "Removing SNVs with any allele < $isMono reads (e.g. when genotype is unknown and dbSNPs are used)\n";
    }
    my $newout = '';
    open(RE, $output) or die "ERROR: cannot open merged SNV file: $output\n";
    while(<RE>){
      chomp;
      my ($chr, $pos, $als, $id, $reads) = split(' ', $_); 
      my ($ref, $alt, $wrt) = split(':', $reads);
      if($ref >= $isMono && $alt >= $isMono){
        $newout .= "$_\n"; # added
	# push to ratios and coverage
	$refcnt += $ref;
	$altcnt += $alt;
	push @rto, $ref/($ref+$alt);
	push @cov, $ref+$alt;
	$n += 1;
      }else{
        $x += 1;
      }
    }
    close(RE);
    
    print "$n SNVs kept; $x mono-allelic SNVs removed\n";
    print "Overwriting $output\n";
    open(WR, ">", $output) or die "ERROR: cannot overwrite SNV file: $output\n";
    print WR $newout;
    close(WR);
  }

  print "Finished merging\n";
  return (\@rto, \@cov, $refcnt, $altcnt);
}

sub printUsage{

  my ($samType) = @_;
  print <<EOT;
USAGE: perl $0 chr input_sam_file input_snvs output_snvs output_bedgraph is_paired_end [is_strand_sp [bedgraph_title]]

NOTE: 	the read processing script is for $samType 
chr			chromosome to be investigated (correspond to the input_sam_file)
input_sam_file 		SAM file input after duplicate removal and merging (use rmDup.pl and mergeSam.pl)
intput_snvs		input SNV list (without read counts)
output_snvs		output SNV candidates with read counts
output_bedgraph		output bedgraph file, see below for the details:
			http://genome.ucsc.edu/goldenPath/help/bedgraph.html
is_paired_end		0: single-end; 1: paired-end
			For paired-end reads, all reads should be paired up, 
			where pair-1 should be always followed by pair-2 in the next line.

OPTIONAL [strongly recommended to be input]:
is_strand_sp		0: non-strand specific (or no input); 
			1: strand-specific with pair 1 **sense**;
			2: strand-specific with pair 1 **anti-sense**
			Be careful with the strand-specific setting as it will give totally opposite 
			strand information if wrongly set.

			The strand-specific option is used for strand-specific RNA-Seq data.
			When set, specialized bedgraph files will be output (output_bedgraph)
			where there is a 5th extra attribute specifying the strand: + or -
			besides the standard ones: http://genome.ucsc.edu/goldenPath/help/bedgraph.html
			One can use grep and cut to get +/- strand only bedgraphs.

OPTIONAL [if input, must be input in order following is_strand_sp]:
bedgraph_title		a short title for the output bedgraph files (will be put in description of the header line)
                        if there are spaces in between it should be quoted
			e.g. "nbt.editing reads: distinct after dup removal"
			if not input, "default" will be used as the short title

EOT
  exit;

  #hidden options:
  #USAGE: perl $0 chr input_sam_file input_snvs output_snvs output_bedgraph is_paired_end [is_strand_sp bedgraph_title discarded_read_pos]
#discarded_read_pos	masked-out (low-quality) read positions in calculating 
#			the max read quality scores, 
#			in 1-based, inclusive, interval (a:b,c:d,... no space) format:
#			e.g. 1:1,61:70 will discard the 1st, 61st-70th read positions.
#			NOTE: the remaining reads will still contain the positions.

}


sub parseArg{
  my ($title, $strandFlag) = @_;

# handling empty title
if(!defined($title)){
  $title = "default"; #default
}
# handling undefined $strandFlag for backward compatibility
if(!defined($strandFlag)){
  print "WARNING: is_strand_sp should be input to specify whether the RNA-Seq data (input_sam_file) are strand specific.\nSet to be 0: non-strand specific for backward compatibility\n";
  $strandFlag = 0;
}elsif($strandFlag == 0){
  print "NOTE: non-strand-specific (default)\n";
}elsif($strandFlag == 1){
  print "IMPORTANT NOTE: pair 1 is sense in the strand-specific setting\n";
}elsif($strandFlag == 2){
  print "IMPORTANT NOTE: pair 1 is anti-sense in the strand-specific setting\n";
}else{
  die "ERROR: have to set a specific strand-specific flag: 0/1/2; unkonwn flag set: $strandFlag\n";
}
 return ($title, $strandFlag);
}

1;
