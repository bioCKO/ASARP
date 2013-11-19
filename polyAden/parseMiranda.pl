#!/usr/bin/perl

use strict;
use warnings;
use Statistics::R; #interact with R
require "mirnaParser.pl"; # needs rc

if(@ARGV < 7){

  print <<EOT;

USAGE: perl $0 ASAT_fasta miRanda_result ctrl_snv_path output ext_miRanda_out energy_th percent_th [mirSVR_results]

ASAT_fasta	the merged fasta file containing all fasta sequences with the reference and alternative alleles from the ASAT results
		The fasta identifier information is important and used in the script
		format: >chr;gene;snv_cordinate;snv_id;ref>alt;ref#:alt#;ASAT_info;snv_pos_in_seq;ref[alt]; ref#[alt#]
		Example:
		>chr10;NRP1;33467312;rs10827206;C>T;370:232;AT:3-(0.6122);26;G;370
		GCTCACAAAGAATAAGCCTGCCTTAGGGCTGGCAACATCTAAGCCTCTAAC
		>chr10;NRP1;33467312;rs10827206;C>T;370:232;AT:3-(0.6122);26;A;232;
		GCTCACAAAGAATAAGACTGCCTTAAGGCTGGCAACATCTAAGCCTCTAAC
		
		Note: the two-allele (ref and alt) sequences should go in pairs; the sequence should be the reverse 
		complement if the SNV is on - strand. The last ref[alt] indicates the allele version of the sequence,
		and is the reverse on - strand (i.e. C>T;370:232 converted to G;370 and A;232 respectively)

miRanda_result	the combined miRanda results for all ASAT cases predicted from ASAT_fasta

ctrl_snv_path	the path to the control SNV files (each with reads for both alleles)

output		the output result file
ext_miRanda_out	the compact extracted results from miRanda_result, with 2 different suffixes of ext_miRanda_out
		.extlst (extracted list containing miRanda miRNA targets only)
		.complst (comparison list containing alignment scores and energies of all miRanda predictions)

energy_th	the (negated) energy cutoff for allele-specific miRNA target comparisons, 
		e.g. 20 means only miRNA targets with energies <= -20 will be compared
percent_th	the percentage cutoff for average normalized energy changes to be considered and output
		e.g. 0.1 and 1.0 mean 10% and 100% average normalized energy changes respectively

EOT
#		.shrtlst (extracted list containing miRanda miRNA targets only)
  exit;
}

my ($asatin, $in, $kdFile, $out, $miRandaExt, $ENRGTH, $MFETH, $mirSVR) = @ARGV;

my $miRnaOut = $miRandaExt.".extlst";
#my $short = $miRandaExt.".shrtlst";
my $comp = $miRandaExt.".complst";

if($ENRGTH >= 0){
  die "ERROR: minimum free energy (MFE) threshold should be <0 (now $ENRGTH)\n";
}
if($MFETH <= 0){
  die "ERROR: absolute minimum free energy (MFE) change percentage threshold change should be >0, e.g. 0.5 for 50% (now $MFETH)\n";
}

# get all allele-specific version fasta information
my ($ansRef, $k) = getAlleleFasta($asatin);

my %ans = %$ansRef;

# get all miRanda results
my $n = 0;
open(FP, $in) or die "ERROR: cannot onpen miRanda result: $in\n";
my $result = "";
#my $shortlist = "";

#my $miHeader = "Seq1,Seq2,Tot Score,Tot Energy,Max Score,Max Energy,Strand,Len1,Len2,Positions";
my $miHeader = "Seq1\tSeq2\tScore\tEnergy\tSeq1_rg\tSeq2_rg\tmatch_len\tp1\tp2";
my $miHeader2 = "Scores for this hit:";

# get all miRanda_result
while(<FP>){
  if(index($_, "Energy:") != -1){
    my $hit = 0;
    my $isScore = 0;
    my $temp = "$_";
    while(<FP>){
      if($isScore){
        # check if the result overlaps the snv position
	my ($miS, $mS, $Sc, $enrg, $miRg, $mRg, $aliLen) = split(/\t/, $_);
	my $miRNA = substr($miS, 1); # remove '>'
        my ($mFrom, $mTo) = split(' ', $mRg);
	my ($chr, $gene, $pos, $id, $als, $cnts, $at, $inPos, $al, $cnt) = split(';', $mS);

        my $flag = filterWithMirSVR($chr, $gene, $pos, $miRNA, $mirSVR);
	#if($Sc < 80){ $flag = 0; }
	if($flag){
	  #print " ($miS, $mS, $Sc, $enrg, $miRg, $mRg: $mFrom, $mTo, $aliLen)\n ($chr, $gene, $pos, $id, $als, $cnts, $at, $inPos, $al, $cnt)\n";
	  if($inPos <= $mTo && $inPos >= $mFrom){
            #$shortlist .= $_;
	    $n += 1; 
	    my $key = "$chr;$gene;$pos;$id;$als;$cnts;$at";
	    my $subkey = "$al;$cnt";
	    my $val = "$miRNA\t$Sc\t$enrg"; #\t$miRg\t$mRg\t$aliLen
	    if(!defined($ans{$key})){
	      my %hs = ($subkey =>"$val\n"); 
	      $ans{$key} = \%hs;
	    }else{
	      if(!defined($ans{$key}->{$subkey})){
	        $ans{$key}->{$subkey} = "$val\n";
	      }else{
	        $ans{$key}->{$subkey} .= "$val\n";
	      }
	    }
	    #print "$_\n";
	  }
	}
	$isScore = 0;
      }
      if($_ eq "Complete\n"){
        $temp .= "$_\n";
        last;
      }
      $temp .= $_; # keep concatenating
      if($_ eq "$miHeader2\n"){
        $hit = 1; # there is a hit inside
	$isScore = 1;
      }
    }
    if($hit){
      $result .= $temp;
    }
  }
}
close(FP);
print "In total $n targets extracted\n";

open(OP, ">", $miRnaOut) or die "ERROR: cannot write to extract file $miRnaOut\n";
print OP $result;
close(OP);

#open(SP, ">", $short) or die "ERROR: cannot write to shortlist file $short\n";
#print SP "$miHeader\n";
#print SP $shortlist;
#close(SP);

open(CP, ">", $comp) or die "ERROR: cannot write to comparison file $comp\n";
# compare ref>alt miRanda target prediction scores
for my $key (keys %ans){
  print CP "$key\n";
  my %hs = %{$ans{$key}};
  my $m = keys %hs;
  for my $al (keys %hs){
#=cut  
    # new: store only the best energy for each miRNA
    my %ens = ();
    my %scs = ();
    my @mirs = split(/\n/, $hs{$al});
    for(@mirs){
      my ($mirna, $sc, $eng) = split(/\t/, $_);
      if(!defined($ens{$mirna})){
        $ens{$mirna} = $eng;
	$scs{$mirna} = $sc;
      }else{
        #print "dup: $mirna $sc $eng\n";
	if($eng < $ens{$mirna}){
	  $ens{$mirna} = $eng;
	  $scs{$mirna} = $sc;
	}
      }
    }
    my $filtered = '';
    for(keys %ens){
      $filtered .= "$_\t$scs{$_}\t$ens{$_}\n";
    }
    $hs{$al} = $filtered;
#=cut
    print CP "$al\n$hs{$al}";
  }
  print CP "\n";
}
close(CP);

#compareEnergy(\%ans);
#my $kdFile = "/home/cyruschan/asarp_perl/U87.DroshaKD/Dro.snvs/U87.DroshaKD.snv.lst";
#my $kdFile = "/home/cyruschan/asarp_perl/gm12878/N.A+/snv.ss.S/N.A+.snv.lst";
my ($outInfo) = compareScoreEnergy(\%ans, $kdFile, $ENRGTH, $MFETH);

open(SP, ">", $out) or die "ERROR: cannot output results to $out\n";
print SP $outInfo;
close(SP);

print "FINISHED\n";


##################################################################################
###########		sub-routines		########
#
#
#
sub filterWithMirSVR{
  my ($chr, $gene, $pos, $miRNA, $mirSVR) = @_;
  if(!defined($mirSVR)){
    return 1;
  }
  my $check = open(MFP, $mirSVR);
  if(!$check){
    print STDERR "$mirSVR not readable! ignore filtering\n";
    return 1;
  }
  close(MFP);

  my $flag = 0;
  # command:
  #my $cmd = "grep -w $gene $mirSVR | cut -f 2,4,7,14,15,16,17,18,19";
  my $cmd = "grep -w $gene $mirSVR | cut -f 2,4,14 | grep '$miRNA'"; # $mir, $gene, $loc
  my $res = qx($cmd);
  my @selected = split(/\n/, $res);
  for my $mtch (@selected){
    my ($mir, $miGene, $loc) = split(/\t/, $mtch);
    #[hg19:3:38524951-38524971:+]
    if($loc =~ /\[hg19:(X|Y|M|\d+):([,\-\d]+):[\+|\-]\]/){
      my ($miChr, $rg) = ($1, $2);
      my @range = split(',', $rg);
      for(@range){
        my ($s, $e) = split('-', $_);
        #print "$mtch\n$miChr, $s, $e\n";
        #if($mir eq $miRNA && $pos >= $s && $pos <= $e){
        if($pos >= $s && $pos <= $e){ # do not require the same miRNA and mir
          print "MATCH!!! $mir $pos\n";
          $flag = 1; last; # no need to search other 
	}
      }
    }else{ die "ERROR: cannot parse $mir $miGene: $loc\n"; }
  }

  return $flag;
}

sub compareScoreEnergy{
  my ($ansRef, $kdSnv, $ENRGTH, $MFETH) = @_;
  my %ans = %$ansRef;
  my $outStr = "Y/N\tchr\tgene\t+/-\tsnv\tid\tASAT\tavgMFE\talleles\tmiRNA(maxMFE)\n";
  # compare ref>alt miRanda target prediction scores
      
  # Create a communication bridge with R and start R
  my $R = Statistics::R->new();
  my ($sig, $insig) = (0, 0); #significant and insignificant counts
  my $TH = 0.05; #0.05; #0.05; #0.05; # p-value threshold

  my ($scY, $scN, $enY, $enN, $seY, $seN) = (0, 0, 0, 0, 0, 0);

  # clustering to get the new energy threshold
  my @alle = (); # all energies
  for my $key (keys %ans){
    my %hs = %{$ans{$key}};
    for my $al (keys %hs){ # sub-key
      my @vals = split(/\n/, $hs{$al});
      for(@vals){
        my ($miR, $sc, $enrg) = split(/\t/, $_);
	push @alle, abs($enrg); # just cluster energies
      }  
    }
  }
  my ($ce0, $ce1) = gCluster(1, abs($ENRGTH), \@alle);
  my $ENRGTH2 = $ENRGTH; #(-$ce1+$ENRGTH)/2; #+abs($ENRGTH))/2; #$ENRGTH;
  my $MFETH2 = abs($ce0-$ce1); #$MFETH;
  if($MFETH2 < $MFETH){
    $MFETH2 = $MFETH;
  }

  for my $key (keys %ans){
    my %hs = %{$ans{$key}};
    my $m = keys %hs; # should be 1 or 2
    
    my %ens = ();
    my %scs = ();
    #print "$key\n";
    my ($chr, $gene, $pos, $id, $als, $cnts, $at) = split(';', $key);
    my $std = '+';
    my ($ref, $alt) = split('>', $als);
    my ($refCnt, $altCnt) = split(':', $cnts);
    if(index($at, 'AT:3-')!= -1 || index($at, 'ASE:3-')!= -1){
      $ref = rc($ref);
      $alt = rc($alt); #reverse complement
      $std = '-';
    }
    my $kd = qx(grep $pos $kdSnv);
    #print "$kd\n";
    my @kds = split(/\n/, $kd);
    my $kdStr = '';
    for(@kds){
      if($_ ne '' && substr($_, -1, 1) eq $std){ # check string
        $kdStr = $_; last;
      }
    }
    if($kdStr ne ''){
      # perform parsing and chi-squared test
      my ($kdChr, $kdPos, $kdAls, $kdId, $kdCnts, $kdStd) = split(' ', $kdStr);
      my ($kdRefCnt, $kdAltCnt) = split(':', $kdCnts);
      # chi-squared
      $R->run("M <- as.table(rbind(c($refCnt, $altCnt), c($kdRefCnt, $kdAltCnt)))");
      $R->run('p = fisher.test(M)$p.value'); #default expected dist is c(0.5, 0.5)
      my $pValue = $R->get('p');

      # direction check:
      #if(($refCnt-$altCnt)*($kdRefCnt-$kdAltCnt) < 0){
      # p-value check
      if($pValue <= $TH){
        $sig += 1;
      }else{
        $insig += 1;
      }
      #print "$key\n$kdStr\n";
      #print "Test ($refCnt, $altCnt), ($kdRefCnt, $kdAltCnt)\np-value: $pValue\n";
    }else{ print "$key not found in control $kdSnv\n\n";  } #next; }
    $scs{"$ref;$refCnt"} = 0; #score
    $scs{"$alt;$altCnt"} = 0; #score
    $ens{"$ref;$refCnt"} = 0; #energy
    $ens{"$alt;$altCnt"} = 0; #energy
    my $details = ''; 
   
    # store the absolute min energy, absolute max score, and the list of hits (no need to distinguish ref and alt)
    my %hits = (); # keys are the two alleles, values are references to miRNA hashes of the two alleles
    for my $al (keys %hs){ # sub-key
      #print "$al\n$hs{$al}";
      #results
      my %mir = ();
      #score
      my $alSc = 0; # score, larger the better
      my $alMirSc = '';
      #energy
      my $alEn = 0; # energy, smaller the better
      my $alMir = '';
      my @vals = split(/\n/, $hs{$al});
      for(@vals){
        my ($miR, $sc, $enrg) = split(/\t/, $_);
        $mir{$miR} = $enrg;
	if($sc > $alSc){ # not used
	  $alSc = $sc;
	  $alMirSc = $miR;
	  # associate the engery with the best alignment score
	  #$alEn = $enrg;
	  #$alMir = $miR;

	}
	if($enrg < $alEn){
	  $alEn = $enrg;
	  $alMir = $miR;
	}
      }
      $scs{$al} = $alSc;
      $ens{$al} = $alEn;
      $hits{$al} = \%mir;
      
      $details .= "$al: max score $alMirSc: $alSc\n";
      #$details .= "$al: aso energy $alMir: $alEn\n";
      $details .= "$al: min energy $alMir: $alEn\n";
    }
    # find the maximal change of MFE (minimum free energy)
    # must distinguish ref and alt (always ref VS alt, otherwise the validation would be invalid)
    my %refhs = ();
    my %alths = ();
    if(defined($hits{"$ref;$refCnt"})){
      %refhs = %{$hits{"$ref;$refCnt"}};
    }
    if(defined($hits{"$alt;$altCnt"})){
      %alths = %{$hits{"$alt;$altCnt"}};
    }
    my $maxMFE = 0;
    my $maxMir = '';
    my ($avgMFE, $avgCnt, $bgMFE, $bgCnt, $bgPlus, $bgMinus, $pCnt, $mCnt, $finalMFE) = (0, 0, 0, 0, 0, 0, 0, 0, 0); #average MEF
    my @bgList = (); # the background set list
    my @bgListP = (); # the background set list
    my @bgListM = (); # the background set list
    #my ($refmir, $altmir) = ('', '');
    # fill in the highest possilbe minimal energy
    for(keys %refhs){
      if(!defined($alths{$_})){ $alths{$_} = -1; } 
    }
    for(keys %alths){
      if(!defined($refhs{$_})){ $refhs{$_} = -1; }
    }

    for(keys %refhs){
      # # now alths{$_} must be defined

      # normalized diff:
      my $norm = abs($refhs{$_});
      if(abs($alths{$_}) < $norm){ $norm = abs($alths{$_}); } # normalization over the smaller one
      my $diff = ($refhs{$_} - $alths{$_});
      # no normalization now #
      #$diff /= $norm; #normalized diff
      # a new filter: energy scores cannot be too low for both alleles
      #print "$_ diff: $diff = ref $refhs{$_} - alt $alths{$_}\n";
      if(abs($diff) > abs($maxMFE)  && ($refhs{$_} <= $ENRGTH2 || $alths{$_} <= $ENRGTH2))
      {
        $maxMFE = $diff; $maxMir = $_;	
      } # only when they are <= threshold
      if(abs($diff) >= $MFETH2) #  && ($refhs{$_} <= $ENRGTH2 || $alths{$_} <= $ENRGTH2))
      {
        #print "$key pass: \n$refhs{$_} and $alths{$_}: $diff\n";
        $avgMFE += $diff; $avgCnt += 1; 
      }
      # all are considered as background
      if(abs($diff) >= $MFETH2) # && ($refhs{$_} <= $ENRGTH2 || $alths{$_} <= $ENRGTH2))
      {
        $bgMFE += $diff; $bgCnt += 1;
	push @bgList, "$diff ";
	if($diff < 0){
	  $bgMinus += $diff; $mCnt += 1;
	  push @bgListM, "$diff ";
	}else{
	  $bgPlus += $diff; $pCnt += 1;
	  push @bgListP, "$diff ";
	}
      }
    }
    if($avgCnt){ $avgMFE /= $avgCnt;  }
    if($bgCnt){ $bgMFE /= $bgCnt;  
      # calculate sample std
    }

    #### debug
    #$avgMFE = $maxMFE;
    #$avgMFE = $bgMFE; #use background
    
    #normaliz background
    if(abs($bgPlus)>0 || abs($bgMinus)>0){
      if($bgPlus){ $bgPlus /= $pCnt; }
      if($bgMinus){ $bgMinus /= $mCnt; }

    }else{
      next;
    }
    
    my $stdev = getStdev(\@bgList, $bgMFE);
    my $stdP = getStdev(\@bgListP, $bgPlus);
    my $stdM = getStdev(\@bgListM, $bgMinus);

    #my @bgListMAbs = ();
    #for(@bgListM){
    #  push @bgListMAbs, abs($_);
    #}
    #if($pCnt == 0 || $mCnt == 0){
    #  next;
    #}
    #my $sign = rankSumTest(\@bgListP, \@bgListMAbs);


    #my $crit = (abs($bgPlus + $bgMinus) - ($stdP+$stdM)); # average distance > sum of stdev
    #if($crit > 0 ){
    #my $foldchange = abs(($bgPlus*$pCnt+0.01)/($bgMinus*$mCnt+0.01));
    #if($foldchange >= 2 || $foldchange <= 0.5) 
    #if(($pCnt-$mCnt)*($bgPlus*$pCnt+$bgMinus*$mCnt) > 0 && ($pCnt-$mCnt)*$avgMFE >0) # double-consistency
    #if(($bgPlus+$bgMinus)*$avgMFE >0) # double-consistency
    #if($sign) #($pCnt-$mCnt)*($bgPlus+$bgMinus) > 0)# && ($pCnt-$mCnt)*$avgMFE >0) # double-consistency
    if($bgPlus*$bgMinus == 0) #$avgMFE)  #*($bgMFE) > 0) # && abs($bgMFE)>=abs($bgMFE) + $stdev)
    {
    #my $FOLD = 1.5;
    #if(defined($refhs{$maxMir}) && 
    #if(
    #(abs($bgPlus)/(abs($bgMinus)+0.1) >= $FOLD && $avgMFE > 0)
    #|| 
    #(abs($bgPlus)/(abs($bgMinus)+0.1) <= 1/$FOLD && $avgMFE < 0)){ 
    ##abs($avgMFE) >abs($bgMFE)+ $stdev  && $avgMFE*$bgMFE >0){ # && abs($avgMFE) > abs($bgMFE)){ # + $stdev){
      $finalMFE = $avgMFE; #$bgPlus+$bgMinus; #$avgMFE; #$pCnt-$mCnt; #($bgPlus*$pCnt+$bgMinus*$mCnt); #$pCnt-$mCnt; #$avgMFE; #$bgPlus;
      #$finalMFE = -1 if ($foldchange <= 0.5);
      #if(abs($bgMinus) > $bgPlus){
      #  $finalMFE = $bgMinus;
      #}
      # sign check
      if($finalMFE * ($refCnt - $altCnt) > 0){
        print "Correct!\n";
	$enY += 1;
      }elsif($finalMFE * ($refCnt - $altCnt) < 0){
        print "Incorrect!\n";
	$enN += 1;
      }
    }
    else{
      #print "Skipped\n";
      next;
    }
    if(defined($refhs{$maxMir})){ # it indicates that $alths{$maxMir} is also defined
      print "$key\nmaxMFE: $maxMir $maxMFE: $ref;$refCnt:$refhs{$maxMir} -- $alt;$altCnt:$alths{$maxMir}\n";
      print "avgMFE: $avgMFE from $avgCnt; bg: $bgMFE from $bgCnt\n"; #@bgList; std: $stdev\n";
      print "bgPlus: $bgPlus ($stdP from $pCnt); bgMinus: $bgMinus ($stdM from $mCnt)\n";
    }else{ #print "No maxMFE cases for $ref, $alt\n"; 
      next;
    }

  }
  $R->stop;
  print "Energy (MFE) threshold: -$ENRGTH; Change percentage threshold: $MFETH\n"; 
  print "Significant $TH: $sig\nInsignificant $TH: $insig\n";
  #print "Y (higher score, fewer reads): $scY\nN (higher score, more reads): $scN\n";
  print "Y (lower energy, fewer reads): $enY\nN (lower energy, more reads): $enN\n";
  #print "Y (hi sc  lo en, fewer reads): $seY\nN (hi sc  lo en, more reads): $seN\n";
  #
  $outStr .= "\nY (lower energy, fewer reads): $enY\nN (lower energy, more reads): $enN\n";
  return $outStr;
}

sub getStdev{
  my ($ref, $avg) = @_;
  my @list = @$ref;
  my $n = @list;
  if($n <= 1){ return 0; }
  if(!defined($avg)){ # need to calculate here
    my $x = 0;
    for(@list){
      $x += $_;
    }
    $avg = $x/$n; # average
  }
  $n = $n - 1; # sample Stdev
  my $sd = 0;
  for(@list){
    $sd += ($_ - $avg)*($_ - $avg);
  }
  if($n > 0){
    return sqrt($sd/$n);
  }
  return 0;

}

sub rankSumTest{

  my ($aRef, $bRef) = @_;
  my $flag = 0;
  my $PVAL = 0.05; 
  # Create a communication bridge with R and start R
  my $R = Statistics::R->new();
  $R->run("x <-c(".join(",", @$aRef).")");
  $R->run("y <-c(".join(",", @$bRef).")");
  #my $out = $R->run("wilcox.test(x, y, \"greater\")");
  #print "$out\n";
  $R->run('p = wilcox.test(x, y, "greater")$p.value');
  my $pValue = $R->get('p');
  if($pValue <= $PVAL){
    $flag = 1;
  }else{
    $R->run('p2 = wilcox.test(x, y, "less")$p.value');
    my $pValue2 = $R->get('p2');
    if($pValue <= $PVAL){
      $flag = -1;
    }
  }
  $R->stop;

  return $flag;
}


sub gCluster{

  my ($c0, $c1, $listRef) = @_;

  my $ITERATION = 50;
  my @list = @$listRef;
  my $lin = @list;
  print "Clustring $lin elements: init: c0: $c0; c1: $c1\n";

    # guided clustering:
    #my ($c0, $c1) = (1, abs($ENRGTH));
    my ($c0n, $c1n) = (0,0); #counts
    for(my $j = 1; $j <= $ITERATION; $j++){
      #batch mode clustering
      my ($oc0, $oc1) = ($c0, $c1); # old centroids
      ($c0, $c1) = (0, 0); # new centroids
      ($c0n, $c1n) = (0,0); #counts
      
      for my $can (@list){
          #my $can = abs($refhs{$_} - $alths{$_});
          my ($d0, $d1) = (abs($can-$oc0), abs($can-$oc1));
          if($d0 < $d1){
	    $c0 += $can;
	    $c0n += 1;
          }else{
	    $c1 += $can;
	    $c1n += 1;
          }
      }
      # compute centroids
      $c0 /= $c0n if ($c0n >0);
      $c1 /= $c1n if ($c1n >0);
      #check onvergence:
      if(abs($c0-$oc0)+abs($c1-$oc1) <= 0.05){
        print STDERR "converged at $j: c0: $c0 -> $oc0 c1: $c1 -> $oc1 \n";
	last;
      }
    }

  return ($c0, $c1); # the new larger centroid
}