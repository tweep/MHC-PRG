#!/usr/bin/env perl 

use strict;
use MHC::Utils::HLAtypeinference; 
use MHC::simpleHLA;

use List::MoreUtils qw/all mesh any /;
use List::Util qw/sum/;
use Data::Dumper;
use Getopt::Long;   
use Sys::Hostname;
use File::Copy;
use File::Basename;
use Storable;
use File::Path;
use File::Spec::Functions;
use File::Which; 

my $kMer_size = 55;  

my $output_dir ;#  = "/gne/research/scratch/users/vogelj4/mhc-prg/out"; # old tmp dir  

my $graph_root_dir ; #= "/gne/home/matthejb/workspace/MHC-PRG/tmp2/";  # old tmp2_dir  

my $hla_nom_dir  ;  #  = "/gne/research/workspace/vogelj4/my_furlani_modules/mhc-prg/data/"; 

# my @testCases = (
	# [[qw/A A/], [qw/A A/]],
	# [[qw/? A/], [qw/A A/]],
	# [[qw/A ?/], [qw/A A/]],
	# [[qw/A T/], [qw/A A/]],
	# [[qw/A A/], [qw/T A/]],
	# [[qw/A C/], [qw/G T/]],
	# [[qw/A C/], [qw/? T/]],
	# [[qw/? C/], [qw/G T/]],
	# [[qw/? ?/], [qw/G T/]],
	# [[qw/? T/], [qw/? T/]],
	# [[qw/? C/], [qw/? T/]],
	
# );
# foreach my $testCase (@testCases)
# {
	# print join(' vs ', map {join('/', @$_)} @$testCase), "   ", join(' ', compatibleStringAlleles($testCase->[0], $testCase->[1])), "\n";
# }
# exit;

# input parameters

my $graph = 'hla';   
my $sampleIDs = '';
my $BAMs = '';
my $actions;
my $trueHLA;
my $trueHaplotypes;
#my $validation_round = 'R1';
my $T = 0;
my $minPropkMersCovered = 0;
my $minCoverage = 0;
my $all_2_dig = 0;
my $only_4_dig = 1;
my $reduce_to_4_dig = 0;
my $HiSeq250bp = 0;
my $MiSeq250bp = 0;

my $fastExtraction = 0;

my $fromPHLAT = 0;
my $fromHLAreporter = 0;

my $referenceGenome;
my $threads = 1;

my $no_fail = 0;
my $vP = '';

my @loci_for_check = qw/A B C DQA1 DQB1 DRB1/;

GetOptions ('graph:s' => \$graph,
 'sampleIDs:s'        => \$sampleIDs, 
 'BAMs:s'             => \$BAMs, 
 'actions:s'          => \$actions, 
 'trueHLA:s'          => \$trueHLA,
 'trueHaplotypes:s'   => \$trueHaplotypes, 
 'referenceGenome:s'  => \$referenceGenome, 
 #'validation_round:s' => \$validation_round,
 'T:s'                => \$T,
 'minCoverage:s'      => \$minCoverage,
 'minPropkMersCovered:s' => \$minPropkMersCovered,
 'all_2_dig:s'       => \$all_2_dig,
 'only_4_dig:s'      => \$only_4_dig,
 'HiSeq250bp:s'      => \$HiSeq250bp, 
 'MiSeq250bp:s'      => \$MiSeq250bp, 
 'fastExtraction:s'  => \$fastExtraction, 
 'fromPHLAT:s'       => \$fromPHLAT,
 'fromHLAreporter:s' => \$fromHLAreporter,
 'reduce_to_4_dig:s' => \$reduce_to_4_dig,
 'threads:s'         => \$threads,
 'no_fail:s'         => \$no_fail,
 'vP:s'              => \$vP,
 'output_dir:s'      => \$output_dir,          # Directory for output  
 'graph_root_dir:s'  => \$graph_root_dir,      # Root dir for all graph files 
 'hla_nom_dir:s'     => \$hla_nom_dir,         # HLA nomenclature file (Source: http://hla.alleles.org/wmda/hla_nom_g.txt) 
);         


check_input($output_dir, $hla_nom_dir, $graph_root_dir); 



die if($fromPHLAT and $fromHLAreporter);
my $fromMHCPRG = ((not $fromPHLAT) and (not $fromHLAreporter));

if($MiSeq250bp and $HiSeq250bp)
{
	die "You activated switches for both HiSeq and MiSeq 250bp data - it is either-or";
}

if($minCoverage)
{
	print "Minimum coverage threshold in place: $minCoverage\n";
}

if($minPropkMersCovered)
{
	print "Threshold for kMer coverage in place: $minPropkMersCovered \n";
}

if($fastExtraction)
{
	$HiSeq250bp = 1;
}

my $genome_graph_file = catfile ($graph_root_dir, "GS_nextGen","hla","derived","Homo_sapiens.GRCh37.60.dna.chromosome.ALL.blockedHLAgraph_k25.ctx");
unless(-e $genome_graph_file)
{
	die "Please set variable \$genome_graph_file to an existing file - the current value $genome_graph_file is not accessible.";
}

my $expected_kMer_file = catfile($graph_root_dir, "GS_nextGen", $graph, "requiredkMers_graph.txt.kmers_25");
unless(-e $expected_kMer_file)
{
	die "Please set variable \$expected_kMer_file to an existing file - the current value $expected_kMer_file is not accessible.";
}

my $exon_folder = catfile($graph_root_dir, "GS_nextGen", $graph ); 
unless(-e $exon_folder)
{
	die "Please provide a kMerified graph -- exon folder not there!";
}


my $use_bin = which "MHC-PRG" ; 
print $use_bin."\n"; 
#my $use_bin = "MHC-PRG" ; 
unless(-e $use_bin)
{
	die "Cannot find expected binary: $use_bin";
}
	
my @BAMs = split(/,/, $BAMs);
my @sampleIDs = split(/,/, $sampleIDs);
if(@sampleIDs)
{
	foreach my $sampleID (@sampleIDs)
	{
		unless($sampleID =~ /^[\w]+$/)
		{
			die "Please provide only sample IDs that consist of 'word' characters (regexp \\w+).";
		}
	}
}	

my $sample_IDs_abbr;
if($sampleIDs =~ /^allSimulations(_\w+)?/)
{
	my $addFilter = $1;
	my @dirs;
	if($addFilter)
	{
		@dirs = grep {$_ =~ /I\d+_simulations${addFilter}/} grep {-d $_} glob("$output_dir/hla/*");
	}
	else
	{
		@dirs = grep {$_ =~ /I\d+_simulations/} grep {-d $_} glob( "$output_dir/hla/*");
	}
	
	@sampleIDs = map {die "Can't parse $_" unless($_ =~ /$output_dir\/hla\/(.+)/); $1} @dirs;
	
	if($sampleIDs =~ /^all_simulations_I(\d+)/i)
	{
		my $iteration = $1;
		@sampleIDs = grep {$_ =~ /^I${iteration}_/i} @sampleIDs;
	}
	
	my $debug = 1;
	if($debug)
	{
		@sampleIDs = grep {die unless($_ =~ /sample(\d+)$/); ($1 < 30)} @sampleIDs;
	}
	
	$sample_IDs_abbr = $sampleIDs;
}
elsif($sampleIDs =~ /^all/)
{
	my @dirs = grep {$_ !~ /simulations/} grep {-d $_} glob("$output_dir/hla/*");
	@sampleIDs = map {die "Can't parse $_" unless($_ =~ /$output_dir\/hla\/(.+)/); $1} @dirs;
	
	if($sampleIDs =~ /^all_I(\d+)/i)
	{
		my $iteration = $1;
		@sampleIDs = grep {$_ =~ /^I${iteration}_/i} @sampleIDs;
	}
	else
	{
		die "Does this make sense?";
		@sampleIDs = grep {$_ =~ /^$sampleIDs/i} @sampleIDs;	
	}
	
	if($actions =~ /v|w/)
	{
		@sampleIDs = @sampleIDs[5 .. $#sampleIDs];
		@sampleIDs = grep {$_ !~ /AA02O9Q_Z2/} @sampleIDs;
		@sampleIDs = grep {$_ !~ /AA02O9R/} @sampleIDs;		
		
		# warn "\n\n\n\n!!!!!!!!!!!!!!!!!!!!!\n\nRemove first five and NA12878 and high-coverage sample for validation!\n\n!!!!!!!!!!!!!!!!!!!!!!!!!\n\n\n";
		# @sampleIDs = @sampleIDs[0 .. 4];
		
		die unless(($actions eq 'v') or ($actions eq 'w'));
	}
	
	$sample_IDs_abbr = $sampleIDs;
}
else
{
	$sample_IDs_abbr = join('_', @sampleIDs);
	if(length($sample_IDs_abbr) > 50)
	{
		$sample_IDs_abbr = substr($sample_IDs_abbr, 0, 50);
	}
}

if(scalar(@sampleIDs) > 5)
{
	#@sampleIDs = @sampleIDs[0 .. 4];
	#warn "\n\n\n\n!!!!!!!!!!!!!!!!!!!!!\n\nLimited samples!\n\n!!!!!!!!!!!!!!!!!!!!!!!!!\n\n\n";
}

#@sampleIDs = $sampleIDs[0]; # todo remove
#warn "\n\n\n\n!!!!!!!!!!!!!!!!!!!!!\n\nLimited samples:\n".join("\n", @sampleIDs)."\n\n!!!!!!!!!!!!!!!!!!!!!!!!!\n\n\n";

# die Dumper(\@sampleIDs, \@BAMs); 

if($actions =~ /p/)
{
	die "No positive (-p) and long-read-positive (-p) filtering at the same time" if($actions =~ /l/);

	unless(@BAMs)
	{
		die "Please provide --BAMs for positive filtering";
	}
	unless($#BAMs == $#sampleIDs)
	{
		die "Please provide an equal number of --BAMs and --sampleIDs";
	}
	
	for(my $bI = 0; $bI <= $#BAMs; $bI++)
	{
		my $BAM = $BAMs[$bI];
		my $sampleID = $sampleIDs[$bI];
		
		unless(-e $BAM)
		{
			die "Specified BAM $BAM (in --BAMs) does not exist!\n";
		}
		
		my $output_file = catfile( $output_dir , "hla", $sampleID, "reads.p"); 
        mkpath(catfile($output_dir, "hla", $sampleID));

		
		my $command = qq($use_bin domode filterReads --input_BAM $BAM --positiveFilter $expected_kMer_file --output_FASTQ $output_file --threads $threads );
		
		if($referenceGenome)
		{
			$command .= qq( --referenceGenome $referenceGenome);
		}	
		else
		{
			die "Positive filtering should use reference genome, deactivate only if you know what you are doing!";
		}
		
		if($HiSeq250bp)
		{
			$command .= qq( --HiSeq250bp);
		}
		
		print "Now executing command:\n$command\n\n";
		
		my $ret = system($command);
		unless($ret == 0)
		{
			die "Command $command failed";
		}
	}
}

if($actions =~ /l1/)
{
	die "No positive (-p) and long-read-positive (-p) filtering at the same time" if($actions =~ /p/);
	
	unless(@BAMs)
	{
		die "Please provide --BAMs for positive filtering";
	}
	unless($#BAMs == $#sampleIDs)
	{
		die "Please provide an equal number of --BAMs and --sampleIDs";
	}
	
	for(my $bI = 0; $bI <= $#BAMs; $bI++)
	{
		my $BAM = $BAMs[$bI];
		my $sampleID = $sampleIDs[$bI];
		
		unless(-e $BAM)
		{
			die "Specified BAM $BAM (in --BAMs) does not exist!\n";
		}
		
		my $output_file = catfile( $output_dir , "hla", $sampleID, "reads.p");  
        mkpath(catfile($output_dir, "hla", $sampleID)); 
		
		my $command = qq($use_bin domode filterLongOverlappingReads --input_BAM $BAM --output_FASTQ $output_file --graphDir ${graph_root_dir}/GS_nextGen/${graph});
		
		if($referenceGenome)
		{
			$command .= qq( --referenceGenome $referenceGenome);
		}	
		
		print "Now executing command:\n$command\n\n";
		
		my $ret = system($command);
		unless($ret == 0)
		{
			die "Command $command failed";
		}		
	}
}


if($actions =~ /l2/)
{
	die "No positive (-p) and long-read-positive (-p) filtering at the same time" if($actions =~ /p/);
	
	unless(@BAMs)
	{
		die "Please provide --BAMs for positive filtering";
	}
	unless($#BAMs == $#sampleIDs)
	{
		die "Please provide an equal number of --BAMs and --sampleIDs";
	}
	
	for(my $bI = 0; $bI <= $#BAMs; $bI++)
	{
		my $BAM = $BAMs[$bI];
		my $sampleID = $sampleIDs[$bI];
		
		my $FASTQ = $BAM . '.fastq';
		
		unless(-e $BAM)
		{
			die "Specified BAM $BAM (in --BAMs) does not exist!\n";
		}

		
		unless(-e $FASTQ)
		{
			die "Specified FASTQ $FASTQ (from --BAMs + .fastq) does not exist!\n";
		}
		
		
		my $output_file = catfile( $output_dir , "hla", $sampleID, "reads.p");  
        mkpath(catfile($output_dir, "hla", $sampleID)); 
		
		my $command = qq($use_bin domode filterLongOverlappingReads2 --input_BAM $BAM --input_FASTQ $FASTQ --output_FASTQ $output_file --graphDir ${graph_root_dir}/GS_nextGen/${graph});
		
		if($referenceGenome)
		{
			$command .= qq( --referenceGenome $referenceGenome);
		}	
		
		print "Now executing command:\n$command\n\n";
		
		my $ret = system($command);
		unless($ret == 0)
		{
			die "Command $command failed";
		}		
	}
}


if($actions =~ /n/)
{
	unless(scalar(@sampleIDs))
	{
		die "Please provide some --sampleIDs for negative filtering.";
	}
		
	my @fastQ_files;
	my @output_files;
	foreach my $sampleID (@sampleIDs)
	{ 
        # REDUNDANT 
		my $fastQ_file = catfile($output_dir, "hla", $sampleID, 'reads.p');
		my $fastQ_file_1 = $fastQ_file.'_1';
		my $fastQ_file_2 = $fastQ_file.'_2'; 

        test_if_file_exists($fastQ_file_1);  
        test_if_file_exists($fastQ_file_2);  

		my $output_file = catfile($output_dir, "hla", $sampleID ,'reads.p.n');
		
		push(@fastQ_files, $fastQ_file);
		push(@output_files, $output_file);
	}
	
	my $fastQ_files = join(',', @fastQ_files);
	my $output_files = join(',', @output_files);
	
	my $command = qq($use_bin domode filterReads --input_FASTQ $fastQ_files --negativeFilter $genome_graph_file --output_FASTQ $output_files --negativePreserveUnique --uniqueness_base ${expected_kMer_file} --uniqueness_subtract ${genome_graph_file});
	
	print "Now executing command:\n$command\n\n";
	
	my $ret = system($command);
	unless($ret == 0)
	{
		die "Command $command failed";
	}	
}


if($actions =~ /a/)
{
	unless(scalar(@sampleIDs))
	{
		die "Please provide some --sampleIDs for alignment.";
	}
		
	my @fastQ_files;
	foreach my $sampleID (@sampleIDs)
	{  
        # REDUNDANT 
		my $fastQ_file = catfile($output_dir, "hla" , $sampleID, 'reads.p.n');
		my $fastQ_file_1 = $fastQ_file.'_1';
		my $fastQ_file_2 = $fastQ_file.'_2'; 

        test_if_file_exists($fastQ_file_1); 
        test_if_file_exists($fastQ_file_2);  

		my $output_file = catfile($output_dir, "hla",$sampleID,"reads.p.n");
		
		push(@fastQ_files, $fastQ_file);
	}
	
	my $fastQ_files = join(',', @fastQ_files);
	
	my $pseudoReferenceGenome = catfile ( $graph_root_dir, "GS_nextGen", $graph, "pseudoReferenceGenome.txt");  
    test_if_file_exists($pseudoReferenceGenome);   

	my $command = qq($use_bin domode alignShortReadsToHLAGraph --input_FASTQ $fastQ_files --graphDir ${graph_root_dir}/GS_nextGen/${graph} --referenceGenome ${pseudoReferenceGenome});
	
	if($MiSeq250bp)
	{
		$command .= ' --MiSeq250bp';
	}
	print "Now executing command:\n$command\n\n";
	
	my $ret = system($command);
	unless($ret == 0)
	{
		die "Command $command failed";
	}
}


if($actions =~ /u/)
{
	unless(scalar(@sampleIDs))
	{
		die "Please provide some --sampleIDs for alignment.";
	}
		
	my @fastQ_files;
	foreach my $sampleID (@sampleIDs)
	{
		my $fastQ_file = catfile( $output_dir, "hla", $sampleID, "reads.p");
		push(@fastQ_files, $fastQ_file);
	}
	
	my $fastQ_files = join(',', @fastQ_files);
	
	my $pseudoReferenceGenome = catfile ( $graph_root_dir, "GS_nextGen", $graph, "pseudoReferenceGenome.txt");  
    test_if_file_exists($pseudoReferenceGenome);   

	my $command = qq($use_bin domode alignLongUnpairedReadsToHLAGraph --input_FASTQ $fastQ_files --graphDir ${graph_root_dir}/GS_nextGen/${graph} --referenceGenome ${pseudoReferenceGenome});
	
	print "Now executing command:\n$command\n\n";
	
	my $ret = system($command);
	unless($ret == 0)
	{
		die "Command $command failed";
	}	
}


if($actions =~ /i/)
{
	unless(scalar(@sampleIDs))
	{
		die "Please provide some --sampleIDs for HLA type inference.";
	}
		
	my @aligned_files;
	my @stdout_files;
	
	my $switch_long_reads;

	foreach my $sampleID (@sampleIDs)
	{
		my $local_switch_long_reads = '';
		my $aligned_file = catfile($output_dir, "hla", $sampleID, "reads.p.n.aligned");  

		unless(-e $aligned_file)
		{
			$aligned_file = catfile($output_dir, "hla", $sampleID, "reads.p.aligned");
			$local_switch_long_reads = '--longUnpairedReads';
			unless(-e $aligned_file)
			{			
				die "Expected file $aligned_file not found";
			}
		}
		
		if(defined $switch_long_reads)
		{
			die unless($switch_long_reads eq $local_switch_long_reads);
		}
		else
		{
			$switch_long_reads = $local_switch_long_reads;
		}
	
		push(@aligned_files, $aligned_file);
		
		my $stdout_file = catfile($output_dir, "hla", $sampleID, "inference.stdout"); 
		push(@stdout_files, $stdout_file);
		
		foreach my $validation_round (qw/R1 R2/)
		{
			my $bestguess_file = catfile($output_dir, "hla" , $sampleID, $validation_round.'_bestguess.txt');
			if(-e $bestguess_file)
			{
				warn "Delete existing best-guess file $bestguess_file";
				unlink($bestguess_file) or die "Cannot delete $bestguess_file";
			}
		}
	}
	die unless(defined $switch_long_reads);
	
	open(FAILEDSAMPLES, '>', '_failedSampleID_inference.txt') or die;
	
	if($no_fail)
	{
		warn "--no_fail 1 active, will try to continue when inference for a sample fails.";
	}
	SAMPLE: for(my $sI = 0; $sI <= $#aligned_files; $sI++)
	{
		my $sampleID = $sampleIDs[$sI];
		my $aligned_file = $aligned_files[$sI];
		my $stdout_file = $stdout_files[$sI];
		
		
		my ($aligned_file_name, $aligned_file_path) = fileparse($aligned_file);
					
		my $command = qq($use_bin domode HLATypeInference --input_alignedReads $aligned_file --graphDir ${graph_root_dir}/GS_nextGen/${graph} --outputDir $output_dir --hlaNomDir $hla_nom_dir ${switch_long_reads} --sampleID $sampleID);

		if($MiSeq250bp)
		{
			$command .= ' --MiSeq250bp ';
		}
			
		$command .= ' > ' . $stdout_file;
		
		print "Now executing command:\n$command\n\n";
						
		my $ret = system($command);			
		
		unless($ret == 0)
		{
			if($no_fail)
			{
				warn "When executing $command, got return code $ret";
				print FAILEDSAMPLES $sampleID, "\n";
				next SAMPLE;		
			}		
			else
			{
				die "When executing $command, got return code $ret";
			}
		}
		
		my $expected_bestguess_file = catfile($aligned_file_path, 'R1_bestguess.txt'); 
        test_if_file_exists($expected_bestguess_file); 
		
		my %l_counter;
		open(F, '<', $expected_bestguess_file) or die "Cannot open $expected_bestguess_file";
		<F>;
		while(<F>)
		{
			my $l = $_;
			die unless($l =~ /^(\w+)\t/);
			$l_counter{$1}++;
		}
		close(F);

		foreach my $locus (@loci_for_check)
		{
			unless($l_counter{$locus} == 2)
			{
				die Dumper("Wrong bestguess count", $locus, $expected_bestguess_file, \%l_counter);
			}
			
			my $bestguess_haplotypes_file =  $aligned_file_path . '/' . 'R2_haplotypes_bestguess_' . $locus . '.txt';
			unless(-e $bestguess_haplotypes_file)
			{
				#die "Expected best-guess haplotypes file cannot be found : ". $bestguess_haplotypes_file;
			}	
		}
	}
}  

if($actions =~ /v/)
{
	my $validation_round = 'R1';
	die "Please specify --trueHLA for validation" unless($trueHLA);
			
	# read reference dataset
	my %reference_data;
	open(REFERENCE, "<", $trueHLA) or die "Cannot open $trueHLA";
	my $headerLine = <REFERENCE>;
	chomp($headerLine);
	$headerLine =~ s/\n//g;
	$headerLine =~ s/\r//g;
	my @header_fields = split(/[\t ]/, $headerLine);
	@header_fields = map {if($_ =~ /HLAD((QA)|(QB)|(RB))$/){$_ .= '1';} $_} @header_fields;	
	while(<REFERENCE>)
	{
		my $line = $_;
		chomp($line);
		
		$line =~ s/\n//g;
		$line =~ s/\r//g;
		
		next unless($line);
		
		my @fields = split(/[\t ]/, $line);
		my %line = (mesh @header_fields, @fields);
		
		my $primary_key = $line{'IndividualID'};
		$reference_data{$primary_key} = \%line;
	}
	close(REFERENCE);
	
	# die Dumper(\%reference_data);
	
	my %imputed_HLA;
	my %imputed_HLA_Q;
	my %imputed_HLA_kMersCovered;
	my %imputed_HLA_avgCoverage;
	my %imputed_HLA_lowCoverage;
	my %imputed_HLA_minCoverage;
	
	my %sample_noI_toI;
	
	my $total_imputations = 0;
	
	my %missing_reference_data;
	
	my $summary_file = 'temp/summary_' . $sample_IDs_abbr . '.txt';	
	open(SUMMARY, '>', $summary_file) or die "Cannot open $summary_file";
	print SUMMARY $sample_IDs_abbr, "\n";
	print SUMMARY "\t", join("\t", qw/Locus N CallRate Accuracy/), "\n";
	foreach my $sampleID (@sampleIDs)
	{
		my $sampleID_noI = $sampleID;
		$sampleID_noI =~ s/^I\d+_//g;
		
		
		my $bestGuess_file;
		
		if($fromPHLAT)
		{
			$bestGuess_file = '/gpfs1/well/gsk_hla/PHLAT/'.$sampleID.'/'.$validation_round.'_bestguess.txt';	
			$bestGuess_file =~ s/I6_WTS/I6_AM_WTS/;
			unless(-e $bestGuess_file)
			{
				warn "Best-guess file $bestGuess_file not existing";
				next;
			}		
		}
		elsif($fromHLAreporter)
		{
			$bestGuess_file = '/gpfs1/well/gsk_hla/HLAreporter/results/'.$sampleID.'/'.$validation_round.'_bestguess.txt';	
			$bestGuess_file =~ s/I6_WTS/I6_AM_WTS/;
			
			unless(-e $bestGuess_file)
			{
				warn "Best-guess file $bestGuess_file not existing";
				next;
			}			
		}
		else
		{
			$bestGuess_file = catfile( $output_dir, "hla", $sampleID, $validation_round.'_bestguess.txt');
			unless(-e $bestGuess_file)
			{
				warn "Best-guess file $bestGuess_file not existing";
				next;
			}		
		}
				  
		open(BESTGUESS, '<', $bestGuess_file) or die "Cannot open $bestGuess_file";
		my $bestguess_header_line = <BESTGUESS>;
		chomp($bestguess_header_line);
		my @bestguess_header_files = split(/\t/, $bestguess_header_line);
		while(<BESTGUESS>)
		{
			my $line = $_;
			chomp($line);
			my @line_fields = split(/\t/, $line);
			my %line_hash = (mesh @bestguess_header_files, @line_fields);
			
			my $Q = $line_hash{'Q1'};
			my $kMersCovered = $line_hash{'proportionkMersCovered'};
			$kMersCovered = 1 unless(defined $kMersCovered);
			
			$imputed_HLA_Q{$line_hash{'Locus'}}{$sampleID_noI}{$line_hash{'Chromosome'}} = $Q;
			$imputed_HLA_kMersCovered{$line_hash{'Locus'}}{$sampleID_noI}{$line_hash{'Chromosome'}} = $kMersCovered;
			
			if(($Q < $T) or ($kMersCovered < $minPropkMersCovered))
			{
				$imputed_HLA{$line_hash{'Locus'}}{$sampleID_noI}{$line_hash{'Chromosome'}} = '??:??';			
			}
			else
			{
				die unless(defined $line_hash{'Allele'});
				$imputed_HLA{$line_hash{'Locus'}}{$sampleID_noI}{$line_hash{'Chromosome'}} = $line_hash{'Allele'};			
			}
			
			$total_imputations++;
			
			
			if($line_hash{'Chromosome'} eq '1')
			{
				$imputed_HLA_avgCoverage{$line_hash{'Locus'}}{$sampleID_noI} = $line_hash{'AverageCoverage'};
				$imputed_HLA_lowCoverage{$line_hash{'Locus'}}{$sampleID_noI} = $line_hash{'CoverageFirstDecile'};
				$imputed_HLA_minCoverage{$line_hash{'Locus'}}{$sampleID_noI} = $line_hash{'MinimumCoverage'};
				
				if($minCoverage and ($line_hash{'MinimumCoverage'} < $minCoverage))
				{
					$imputed_HLA{$line_hash{'Locus'}}{$sampleID_noI}{$line_hash{'Chromosome'}} = '??:??';								
				}
			}
		}	
		close(BESTGUESS);
		
		die if(exists $sample_noI_toI{$sampleID_noI});
		$sample_noI_toI{$sampleID_noI} = $sampleID;
	}
	
	print "\nTotal imputations (for comparisons): ", $total_imputations, "\n";
		
	my $debug = 0;
	my $comparisons = 0;
	my $compare_problems = 0;
	my %locus_avgCoverages;
	my %locus_lowCoverages;
	my %locus_minCoverages;
	my @allLoci_allIndivs_avgCoverage;
	
	my %problem_locus_detail;
	my %problem_locus_examined;
	my %problem_haplo_counter;
	my %problem_haplo_detail;
	my %imputations_predictions;
	my %reference_predictions;
	my %imputed_HLA_Calls;
	my %quality_measures; # not used
	my $pileup_href = {};
	
	# die Dumper(\%imputed_HLA);
	
	my @loci = sort keys %imputed_HLA;
	
	# die Dumper(\@loci);
	
	my $process_quality_measures = sub {};
	
	my $PP_to_basket = sub {
		my $PP = shift;
		die unless(($PP >= 0) && ($PP <= 1));
		my $basket = int($PP * 10);
		$basket = 9 if($basket == 10);
		return $basket;			
	};
	
	
	my $fh_qualityMetricsRunning;
	if($fromMHCPRG)
	{
		open($fh_qualityMetricsRunning, '>>', '_qualityMetrics_per_imputation_running.txt') or die;
	}
		
	my %errors_per_sample;
	my %validated_per_sample;
	my %types_as_validated;
	foreach my $locus (@loci)
	{		
		my $arbitraty_indiv = (keys %reference_data)[0];
		next unless((defined $reference_data{$arbitraty_indiv}{'HLA'.$locus}));
		
		my %calibration_baskets;
		my %coverage_over_samples;
		my %coverage_over_samples_individualValues;
		my $coverage_over_samples_nSamples = 0;
		
	
		my $add_to_calibration_basket = sub {
			my $str_correct = shift;
			my $PP = shift;
			my $weight = shift;
			my $locus = shift;
			my $sampleID = shift;
			my $kMer_correct = shift;
			
			die unless(($str_correct eq 'correct') or ($str_correct eq 'incorrect'));
			die unless(defined $PP);
			die unless(defined $weight);
			die unless(defined $kMer_correct);
			
			push(@{$calibration_baskets{$PP_to_basket->($PP)}{$str_correct}}, {PP => $PP, weight => $weight});
			
			if($fromMHCPRG)
			{
				my $correct_numeric = ($str_correct eq 'correct') ? 1 : 0;
				print ${fh_qualityMetricsRunning} join("\t", $sampleID, $vP, $locus, $correct_numeric, $PP, $kMer_correct), "\n";
			}
		};	
		
		$problem_locus_examined{$locus} = 0;
		$problem_locus_detail{$locus} = 0;
		my @indivIDs = keys %{$imputed_HLA{$locus}};
		my $indivI_processedForEvaluation = -1;
		INDIV: foreach my $indivID (@indivIDs)
		{	
			$| = 1;
			
			# print "\t", $indivID, "\t", $locus, "\n";
						
			$debug = 0;
			
			my @imputed_hla_values = map { $imputed_HLA{$locus}{$indivID}{$_} } keys %{$imputed_HLA{$locus}{$indivID}};
			
			if(grep {simpleHLA::autoHLA_is2digit($_)} @imputed_hla_values)
			{
				die "Warning: 2-digit alleles detected in the inference set\n" . Dumper(\@imputed_hla_values); # 2-digit test
			}
		
			my @imputed_hla_values_propkMersCovered = map { my $r = $imputed_HLA_kMersCovered{$locus}{$indivID}{$_}; die unless(defined $r); $r } keys %{$imputed_HLA{$locus}{$indivID}};
			my @imputed_hla_values_q = map { my $r = $imputed_HLA_Q{$locus}{$indivID}{$_}; die unless(defined $r); $r } keys %{$imputed_HLA{$locus}{$indivID}};
			
			die "Undefined HLA ".join(', ', @imputed_hla_values) unless(scalar(grep {defined $_} @imputed_hla_values) == scalar(@imputed_hla_values));
					
			my @reference_hla_values;
			
			next INDIV unless($#imputed_hla_values == 1);
			
			my $reference_lookup_ID = $indivID;
			if($reference_lookup_ID =~ /^downsample_/)
			{
				$reference_lookup_ID =~ s/^downsample_(I\d+_)?//;
				$reference_lookup_ID =~ s/_DSC\d+_\d+//;				
			}
			if($reference_lookup_ID =~ /^C_Platinum_/)
			{
				$reference_lookup_ID =~ s/C_Platinum_//;
				
			}			
			unless(exists $reference_data{$reference_lookup_ID})
			{
				$missing_reference_data{$reference_lookup_ID}{$locus}++;
				# warn "No reference data for $locus $indivID";
			}
			next INDIV unless(exists $reference_data{$reference_lookup_ID});
			
			$reference_data{$reference_lookup_ID}{'HLA'.$locus} or die;
			
			if($reference_data{$reference_lookup_ID}{'HLA'.$locus})
			{
				@reference_hla_values = split(/\//, $reference_data{$reference_lookup_ID}{'HLA'.$locus});
			}
			
			$types_as_validated{$reference_lookup_ID}{$locus} = \@reference_hla_values;

			die Dumper("Weird", $reference_data{$reference_lookup_ID}, \@reference_hla_values) unless($#reference_hla_values == 1);				
						
			die "Undefined HLA ".join(', ', @reference_hla_values) unless(scalar(grep {defined $_} @reference_hla_values) == scalar(@reference_hla_values));			
			@reference_hla_values = grep {! &simpleHLA::modernHLA_is_missing($_)} @reference_hla_values;

			if($#reference_hla_values == -1)
			{
				$missing_reference_data{$reference_lookup_ID}{$locus}++;
				next;
			}
						
			if($only_4_dig)
			{
				next unless (&simpleHLA::HLA_is4digit($reference_hla_values[0]) and (($#reference_hla_values == 0) || (&simpleHLA::HLA_is4digit($reference_hla_values[1]))));
			}
			
			if($reduce_to_4_dig)
			{
				my @reference_hla_values_before = @reference_hla_values;
				@reference_hla_values = map {
					my @inputAlleles = split(/;/, $_);
					join(';', map {simpleHLA::HLA_4digit($_)} @inputAlleles)		
				} @reference_hla_values;
				
				print "Before:\n\t".join(' / ', @reference_hla_values_before), "\n";
				print "After:\n\t".join(' / ', @reference_hla_values), "\n\n";
			}
					
			$imputed_HLA_Calls{$locus}{sum} += scalar(@imputed_hla_values);		
			$indivI_processedForEvaluation++;
			
			my @imputed_present = map {(! &simpleHLA::is_missing($_)) ? 1 : 0} @imputed_hla_values;
			my @imputed_hla_values_q_new;
			my @imputed_hla_values_propkMersCovered_new;
			for(my $i = 0; $i <= $#imputed_hla_values; $i++)
			{
				my $Q = $imputed_hla_values_q[$i];
				my $kP = $imputed_hla_values_propkMersCovered[$i];
				
				die unless(defined $Q);
				die unless(defined $kP);
				die unless(defined $imputed_present[$i]);
				
				if($imputed_present[$i])
				{
					push(@imputed_hla_values_q_new, $Q);
					push(@imputed_hla_values_propkMersCovered_new, $kP);
				}
			}
			
			@imputed_hla_values = grep {! &simpleHLA::is_missing($_)} @imputed_hla_values;
			@imputed_hla_values_q = @imputed_hla_values_q_new;
			@imputed_hla_values_propkMersCovered = @imputed_hla_values_propkMersCovered_new;
			
			die unless($#imputed_hla_values == $#imputed_hla_values_q);
			die unless($#imputed_hla_values == $#imputed_hla_values_propkMersCovered);
			
			$imputed_HLA_Calls{$locus}{called} += scalar(@imputed_hla_values);
			
			if($all_2_dig)
			{
				@reference_hla_values = map {join(';', map {&simpleHLA::autoHLA_2digit($_)} split(/;/, $_))} @reference_hla_values;
				@imputed_hla_values = map {join(';', map {&simpleHLA::autoHLA_2digit($_)} split(/;/, $_))} @imputed_hla_values;
			}
					
			if($locus eq 'B')
			{
			#	print Dumper($indivID, \@reference_hla_values, \@imputed_hla_values), "\n";
			}
			my $comparisons_before = $comparisons;
			my $problem_locus_detail_before = $problem_locus_detail{$locus};
			my $problem_locus_examined_before = $problem_locus_examined{$locus};
			
			if($#imputed_hla_values == 1)
			{
				if($#reference_hla_values > -1)
				{
					if($#reference_hla_values == 0)
					{
						if(&compatibleAlleles_individual($locus, $reference_hla_values[0], $imputed_hla_values[0]) or &compatibleAlleles_individual($locus, $reference_hla_values[0], $imputed_hla_values[1]))
						{
							$comparisons++;
							$problem_locus_examined{$locus}++;
							
							if(&compatibleAlleles_individual($locus, $reference_hla_values[0], $imputed_hla_values[0]))
							{
								$reference_predictions{$locus}{$reference_hla_values[0]}{correct}++;
								$imputations_predictions{$locus}{$imputed_hla_values[0]}{correct}++;
								
								$add_to_calibration_basket->('correct', $imputed_hla_values_q[0], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[0]);														
							}
							elsif(&compatibleAlleles_individual($locus, $reference_hla_values[0], $imputed_hla_values[1]))
							{
								$reference_predictions{$locus}{$reference_hla_values[0]}{correct}++;
								$imputations_predictions{$locus}{$imputed_hla_values[1]}{correct}++;

								$add_to_calibration_basket->('correct', $imputed_hla_values_q[1], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[1]);								
							}
							
							$process_quality_measures->($locus, $quality_measures{$indivID}, 1, 1);
							
						}	
						else
						{
							$comparisons++;
							$compare_problems++;
							$problem_haplo_counter{$indivID}++;
							$problem_haplo_detail{$indivID}{$locus} = 'Reference: '.join('/', @reference_hla_values).' VS Imputed: '.join('/', @imputed_hla_values).'   (1 problem of 1)';
							$problem_locus_detail{$locus}++;
							$problem_locus_examined{$locus}++;
							
							$reference_predictions{$locus}{$reference_hla_values[0]}{incorrect}++;
							$imputations_predictions{$locus}{$imputed_hla_values[0]}{incorrect} += 0.5;
							$imputations_predictions{$locus}{$imputed_hla_values[1]}{incorrect} += 0.5;
							
							$add_to_calibration_basket->('incorrect', $imputed_hla_values_q[0], 0.5, $locus, $indivID, $imputed_hla_values_propkMersCovered[0]);
							$add_to_calibration_basket->('incorrect', $imputed_hla_values_q[1], 0.5, $locus, $indivID, $imputed_hla_values_propkMersCovered[1]);
							
							
							$process_quality_measures->($locus, $quality_measures{$indivID}, 0, 1);
						}
					}
					elsif($#reference_hla_values == 1)
					{
						if(&compatibleAlleles_individual($locus, $reference_hla_values[0], $imputed_hla_values[0]) and &compatibleAlleles_individual($locus, $reference_hla_values[1], $imputed_hla_values[1]))
						{
							$comparisons += 2;
							$problem_locus_examined{$locus} += 2;
							
							$reference_predictions{$locus}{$reference_hla_values[0]}{correct}++;
							$imputations_predictions{$locus}{$imputed_hla_values[0]}{correct}++;	
							$reference_predictions{$locus}{$reference_hla_values[1]}{correct}++;
							$imputations_predictions{$locus}{$imputed_hla_values[1]}{correct}++;	
							
							$process_quality_measures->($locus, $quality_measures{$indivID}, 2, 2);	
							
							$add_to_calibration_basket->('correct', $imputed_hla_values_q[0], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[0]);
							$add_to_calibration_basket->('correct', $imputed_hla_values_q[1], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[1]);
							
						}		
						elsif(&compatibleAlleles_individual($locus, $reference_hla_values[0], $imputed_hla_values[1]) and &compatibleAlleles_individual($locus, $reference_hla_values[1], $imputed_hla_values[0]))
						{
							$comparisons += 2;
							$problem_locus_examined{$locus} += 2;
							
							$reference_predictions{$locus}{$reference_hla_values[0]}{correct}++;
							$imputations_predictions{$locus}{$imputed_hla_values[0]}{correct}++;					
							$reference_predictions{$locus}{$reference_hla_values[1]}{correct}++;
							$imputations_predictions{$locus}{$imputed_hla_values[1]}{correct}++;			
							
							$process_quality_measures->($locus, $quality_measures{$indivID}, 2, 2);		

							$add_to_calibration_basket->('correct', $imputed_hla_values_q[0], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[0]);
							$add_to_calibration_basket->('correct', $imputed_hla_values_q[1], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[1]);
							
						}
						else
						{
							if(
								&compatibleAlleles_individual($locus, $reference_hla_values[0], $imputed_hla_values[0]) or &compatibleAlleles_individual($locus, $reference_hla_values[1], $imputed_hla_values[1]) or
								&compatibleAlleles_individual($locus, $reference_hla_values[1], $imputed_hla_values[0]) or &compatibleAlleles_individual($locus, $reference_hla_values[0], $imputed_hla_values[1])
							)
							{
								$comparisons += 2;
								$compare_problems++;
								$problem_haplo_counter{$indivID}++;
								$problem_haplo_detail{$indivID}{$locus} = 'Reference: '.join('/', @reference_hla_values).' VS Imputed: '.join('/', @imputed_hla_values).'   (1 problem of 2)';						
								$problem_locus_detail{$locus}++;
								$problem_locus_examined{$locus} += 2;
								
								if(&compatibleAlleles_individual($locus, $reference_hla_values[0], $imputed_hla_values[0]))
								{
									$reference_predictions{$locus}{$reference_hla_values[0]}{correct}++;
									$imputations_predictions{$locus}{$imputed_hla_values[0]}{correct}++;					
									$reference_predictions{$locus}{$reference_hla_values[1]}{incorrect}++;
									$imputations_predictions{$locus}{$imputed_hla_values[1]}{incorrect}++;		

									$add_to_calibration_basket->('correct', $imputed_hla_values_q[0], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[0]);
									$add_to_calibration_basket->('incorrect', $imputed_hla_values_q[1], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[1]);									
								}
								elsif(&compatibleAlleles_individual($locus, $reference_hla_values[1], $imputed_hla_values[1]))
								{
									$reference_predictions{$locus}{$reference_hla_values[1]}{correct}++;
									$imputations_predictions{$locus}{$imputed_hla_values[1]}{correct}++;					
									$reference_predictions{$locus}{$reference_hla_values[0]}{incorrect}++;
									$imputations_predictions{$locus}{$imputed_hla_values[0]}{incorrect}++;		
									
									$add_to_calibration_basket->('correct', $imputed_hla_values_q[1], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[1]);
									$add_to_calibration_basket->('incorrect', $imputed_hla_values_q[0], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[0]);	
								}
								elsif(&compatibleAlleles_individual($locus, $reference_hla_values[1], $imputed_hla_values[0]))
								{
									$reference_predictions{$locus}{$reference_hla_values[1]}{correct}++;
									$imputations_predictions{$locus}{$imputed_hla_values[0]}{correct}++;					
									$reference_predictions{$locus}{$reference_hla_values[0]}{incorrect}++;
									$imputations_predictions{$locus}{$imputed_hla_values[1]}{incorrect}++;	
									
									$add_to_calibration_basket->('correct', $imputed_hla_values_q[0], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[0]);
									$add_to_calibration_basket->('incorrect', $imputed_hla_values_q[1], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[1]);	
								}
								elsif(&compatibleAlleles_individual($locus, $reference_hla_values[0], $imputed_hla_values[1]))
								{
									$reference_predictions{$locus}{$reference_hla_values[0]}{correct}++;
									$imputations_predictions{$locus}{$imputed_hla_values[1]}{correct}++;					
									$reference_predictions{$locus}{$reference_hla_values[1]}{incorrect}++;
									$imputations_predictions{$locus}{$imputed_hla_values[0]}{incorrect}++;		

									$add_to_calibration_basket->('correct', $imputed_hla_values_q[1], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[1]);
									$add_to_calibration_basket->('incorrect', $imputed_hla_values_q[0], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[0]);										
								}
								
								$process_quality_measures->($locus, $quality_measures{$indivID}, 1, 2);
							}
							else
							{
								$comparisons += 2;
								$compare_problems += 2;
								$problem_haplo_counter{$indivID} += 2;
								$problem_haplo_detail{$indivID}{$locus} = 'Reference: '.join('/', @reference_hla_values).' VS Imputed: '.join('/', @imputed_hla_values).'   (2 problems of 2)';						
								$problem_locus_detail{$locus} += 2;
								$problem_locus_examined{$locus} += 2;
								
								$reference_predictions{$locus}{$reference_hla_values[0]}{incorrect}++;
								$imputations_predictions{$locus}{$imputed_hla_values[0]}{incorrect}++;					
								$reference_predictions{$locus}{$reference_hla_values[1]}{incorrect}++;
								$imputations_predictions{$locus}{$imputed_hla_values[1]}{incorrect}++;	
								
								$add_to_calibration_basket->('incorrect', $imputed_hla_values_q[0], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[0]);
								$add_to_calibration_basket->('incorrect', $imputed_hla_values_q[1], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[1]);									
								
								$process_quality_measures->($locus, $quality_measures{$indivID}, 0, 2);						
							}
						}																
					}
					else
					{
						die;
					}
				}
			}
			elsif($#imputed_hla_values == 0)
			{
				if($#reference_hla_values > -1)
				{
					if($#reference_hla_values == 0)
					{
						if(&compatibleAlleles_individual($locus, $reference_hla_values[0], $imputed_hla_values[0]))
						{
							$comparisons++;
							$problem_locus_examined{$locus}++;
							$reference_predictions{$locus}{$reference_hla_values[0]}{correct}++;
							$imputations_predictions{$locus}{$imputed_hla_values[0]}{correct}++;
							
							$add_to_calibration_basket->('correct', $imputed_hla_values_q[0], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[0]);
								
							$process_quality_measures->($locus, $quality_measures{$indivID}, 1, 1);
							
						}	
						else
						{
							$comparisons++;
							$compare_problems++;
							$problem_haplo_counter{$indivID}++;
							$problem_haplo_detail{$indivID}{$locus} = 'Reference: '.join('/', @reference_hla_values).' VS Imputed: '.join('/', @imputed_hla_values).'   (1 problem of 1)';
							$problem_locus_detail{$locus}++;
							$problem_locus_examined{$locus}++;
							
							$reference_predictions{$locus}{$reference_hla_values[0]}{incorrect}++;
							$imputations_predictions{$locus}{$imputed_hla_values[0]}{incorrect}++;
							
							$add_to_calibration_basket->('incorrect', $imputed_hla_values_q[0], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[0]);
							
							$process_quality_measures->($locus, $quality_measures{$indivID}, 0, 1);									
						}					
					}
					elsif($#reference_hla_values == 1)
					{
						if(&compatibleAlleles_individual($locus, $reference_hla_values[0], $imputed_hla_values[0]) or &compatibleAlleles_individual($locus, $reference_hla_values[1], $imputed_hla_values[0]))
						{
							$comparisons += 1;
							$problem_locus_examined{$locus} += 1;
							
							if(&compatibleAlleles_individual($locus, $reference_hla_values[0], $imputed_hla_values[0]))
							{
								$reference_predictions{$locus}{$reference_hla_values[0]}{correct}++;
								$imputations_predictions{$locus}{$imputed_hla_values[0]}{correct}++;

								$add_to_calibration_basket->('correct', $imputed_hla_values_q[0], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[0]);
								
							}
							elsif(&compatibleAlleles_individual($locus, $reference_hla_values[1], $imputed_hla_values[0]))
							{
								$reference_predictions{$locus}{$reference_hla_values[1]}{correct}++;
								$imputations_predictions{$locus}{$imputed_hla_values[0]}{correct}++;	

								$add_to_calibration_basket->('correct', $imputed_hla_values_q[0], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[0]);								
							}
							
							$process_quality_measures->($locus, $quality_measures{$indivID}, 1, 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[0]);

						}		
						else
						{
							$comparisons++;
							$compare_problems++;
							$problem_haplo_counter{$indivID}++;
							$problem_haplo_detail{$indivID}{$locus} = 'Reference: '.join('/', @reference_hla_values).' VS Imputed: '.join('/', @imputed_hla_values).'   (1 problem of 1)';
							$problem_locus_detail{$locus}++;
							$problem_locus_examined{$locus}++;
							
							$reference_predictions{$locus}{$reference_hla_values[0]}{incorrect} += 0.5;
							$reference_predictions{$locus}{$reference_hla_values[1]}{incorrect} += 0.5;
							$imputations_predictions{$locus}{$imputed_hla_values[0]}{incorrect}++;	
							
							$add_to_calibration_basket->('incorrect', $imputed_hla_values_q[0], 1, $locus, $indivID, $imputed_hla_values_propkMersCovered[0]);

							$process_quality_measures->($locus, $quality_measures{$indivID}, 0, 1);								
						}
					}
					else
					{
						die;
					}
				}		
			}
			
			my $thisIndiv_problems = $problem_locus_detail{$locus} - $problem_locus_detail_before;
			$errors_per_sample{$indivID} += $thisIndiv_problems;
			
			my $thisIndiv_examined = $problem_locus_examined{$locus} - $problem_locus_examined_before;
			$validated_per_sample{$indivID} += $thisIndiv_examined;
							
			my $avgCoverage = $imputed_HLA_avgCoverage{$locus}{$indivID};
			my $lowCoverage = $imputed_HLA_lowCoverage{$locus}{$indivID};
			my $minCoverage = $imputed_HLA_minCoverage{$locus}{$indivID};

			# average coverages
			if(($thisIndiv_problems > 0))
			{
				push(@{$locus_avgCoverages{$locus}{problems}}, $avgCoverage);
				push(@{$locus_lowCoverages{$locus}{problems}}, $lowCoverage);
				push(@{$locus_minCoverages{$locus}{problems}}, $minCoverage);
			}
			else
			{
				push(@{$locus_avgCoverages{$locus}{ok}}, $avgCoverage);
				push(@{$locus_lowCoverages{$locus}{ok}}, $lowCoverage);
				push(@{$locus_minCoverages{$locus}{ok}}, $minCoverage);	
			}
			
			push (@allLoci_allIndivs_avgCoverage, $avgCoverage);
			
			# print "\t", $thisIndiv_problems, "\n";
			
			# just for debugging - deactivated
			if($thisIndiv_problems == 0)
			{
				if($locus eq 'A')
				{
					# print join(' vs ', join('/', @reference_hla_values), join('/', @imputed_hla_values)), "\n";
				}	
			}
			
			my $thisIndiv_comparions = $comparisons - $comparisons_before;
			my $thisIndiv_OK = $thisIndiv_comparions - $thisIndiv_problems;
			
			my $indivID_withI = $sample_noI_toI{$indivID};
			die unless(defined $indivID_withI);			
            # replace with $output_dir 	 
            my $pileup_fn =  $validation_round."_pileup_".$locus.".txt"; 
			my $pileup_file = catfile(  $output_dir , "hla", $indivID_withI , $pileup_fn );
				
			#my $pileup_file = $output_dir . "/hla" qq(../${tmp_dir}/hla/$indivID_withI/${validation_round}_pileup_${locus}.txt);
			# my $coverages_href = load_coverages_from_pileup($pileup_file);
			my $coverages_href = {};
			my @k_coverages_existing;
			if($indivI_processedForEvaluation > 0)
			{
				foreach my $exon (keys %coverage_over_samples)
				{
					foreach my $exonPos (keys %{$coverage_over_samples{$exon}})
					{
						push(@k_coverages_existing, $exon . '-/-' . $exonPos);
					}
				}					
			}
			

			my @k_coverages_thisSample;
			foreach my $exon (keys %$coverages_href)
			{
				foreach my $exonPos (keys %{$coverages_href->{$exon}})
				{
					$coverage_over_samples{$exon}{$exonPos} += $coverages_href->{$exon}{$exonPos};
					push(@{$coverage_over_samples_individualValues{$exon}{$exonPos}}, $coverages_href->{$exon}{$exonPos});
					push(@k_coverages_thisSample, $exon . '-/-' . $exonPos);
				}
			}	
			$coverage_over_samples_nSamples++;
			
			if($indivI_processedForEvaluation > 0)
			{
				my ($n_shared, $aref_l1_excl, $aref_l2_excl) = list_comparison(\@k_coverages_existing, \@k_coverages_thisSample);
				if(($#{$aref_l1_excl} == -1) and ($#{$aref_l2_excl} == -1))
				{	
					die unless($n_shared == scalar(@k_coverages_existing));
					die unless($n_shared == scalar(@k_coverages_thisSample));					
				}
				else
				{
					die Dumper("There is a problem with per-exon coverage numbers.", $indivI_processedForEvaluation, scalar(@k_coverages_existing), scalar(@k_coverages_thisSample), scalar(@$aref_l1_excl), scalar(@$aref_l2_excl));
				}
			}

			if(($thisIndiv_problems > 0) and (not $all_2_dig) and not ($fromPHLAT) and not($fromHLAreporter))
			{
				my %readIDs;
				
				unless(-e $pileup_file)
				{
					die "Can't find pileup file $pileup_file";
				}
				
				load_pileup($pileup_href, $pileup_file, $indivID_withI);

			
				my $output_fn = catfile($output_dir, "hla_validation", "pileup_".$validation_round."_".$indivID_withI."_".$locus.".txt");
				open(my $output_fh, '>', $output_fn) or die "Cannot open $output_fn";
				print $output_fh join("\t", $indivID_withI, $locus, $thisIndiv_OK), "\n";
				
				unless(scalar(@imputed_hla_values) == 2)
				{
					warn "Can't produce pileup for $locus / $indivID";
					next;
				}
				
				my $inferred = \@imputed_hla_values;				
				my $truth = \@reference_hla_values;
				
				print {$output_fh} $inferred->[0], "\t\t\t", $truth->[0], "\n";
				print {$output_fh} $inferred->[1], "\t\t\t", $truth->[1], "\n\n";
				
				print {$output_fh} join("\t", "Inferred", "", "", "Apparently true", ""), "\n";
				
				my @exons = print_which_exons($locus);				
				my @inferred_trimmed = twoClusterAlleles($inferred);
				
				foreach my $exon (@exons)
				{
					my $file = find_exon_file($locus, $exon,$exon_folder);
					my $sequences = read_exon_sequences($file);
					my $randomKey = (keys %$sequences)[0];
					my $randomSequence = $sequences->{$randomKey};
					$randomSequence =~ s/./?/g;
					$sequences->{'?'} = $randomSequence;
					
					# die Dumper($truth, $inferred);
										
					my @validated_extended = twoValidationAlleles_2_proper_names($truth, $locus, $sequences);
								
					my $oneAllele = (keys %$sequences)[0];
					my $length = length($sequences->{$oneAllele});
										
					# print "-", $sequences->{$oneAllele}, "-\n\n";
					
					die Dumper("No sequences?", \@validated_extended) unless(scalar(grep {$sequences->{$_}} @validated_extended) == 2);
					die unless(scalar(grep {$sequences->{$_}} @inferred_trimmed) == 2);
					
					print {$output_fh} join("\t",
						$inferred_trimmed[0].' Exon '.$exon,
						$inferred_trimmed[1].' Exon '.$exon,
						"",
						$validated_extended[0].' Exon '.$exon,
						$validated_extended[1].' Exon '.$exon,
						), "\n";
					
					# print Dumper($locus, [keys %{$pileup_href->{$indivID_withI}}]);

					for(my $i = 0; $i < $length; $i++)
					{
						my @chars_for_print;
						
						
						push(@chars_for_print, map {substr($sequences->{$_}, $i, 1)} @inferred_trimmed);
						push(@chars_for_print, '');
						push(@chars_for_print, map {substr($sequences->{$_}, $i, 1)} @validated_extended);
						
						if($chars_for_print[0] ne $chars_for_print[1])
						{
							$chars_for_print[2] = '!';
						}
						
						if($chars_for_print[0] ne $chars_for_print[3])
						{
							$chars_for_print[5] = '!';
						}
						else
						{
							$chars_for_print[5] = '';
						}
						
						if($chars_for_print[1] ne $chars_for_print[4])
						{
							$chars_for_print[6] = '!';
						}			
						else
						{
							$chars_for_print[6] = '';				
						}
						
				
						if(exists $pileup_href->{$indivID_withI}{'HLA'.$locus})
						{
							my $pileUpString = $pileup_href->{$indivID_withI}{'HLA'.$locus}[$exon-2][$i];
							die unless(defined $pileup_href->{$indivID_withI});
							die unless(defined $pileup_href->{$indivID_withI}{'HLA'.$locus});
							die unless(defined $pileup_href->{$indivID_withI}{'HLA'.$locus}[$exon-2]);
							# die "Problem with pileup for $locus / $indivID / $exon / $i " unless(defined $pileUpString);
							# next unless(defined $pileUpString);
							
							
							# die Dumper("Pileup too short", $length, scalar(@{$pileup_href->{$indivID_withI}{'HLA'.$locus}[$exon-2]})) unless(defined $pileUpString);
							unless(($chars_for_print[5] eq '!') or ($chars_for_print[6] eq '!'))
							{
								# $pileUpString =~ s/\[.+?\]//g;
							}
							
							my $printPileUpDetails = (1 or (($chars_for_print[5] eq '!') or ($chars_for_print[6] eq '!')));
			
							my $getShortRead = sub {
								my $read = shift;
								my $rE = shift;
								
								my @readIDs = split(/ /, $read);
								die unless($#readIDs == 1);
								
								
								
								my $rI; 
								if(exists $readIDs{$readIDs[0]})
								{
									$rI = $readIDs{$readIDs[0]};
								}
								else
								{
									my $nR = scalar(keys %readIDs);
									$nR++;
									$rI = "Read${nR}X";
									$readIDs{$readIDs[0]} = $rI;
									$readIDs{$readIDs[1]} = $rI;
								}
								
								if($printPileUpDetails)
								{
									return $rI.$rE;
								}
								else
								{
									return $rE;
								}
							};
							
							$pileUpString =~ s/(\@\@.+?)(\](\,|$))/$getShortRead->($1, $2);/ge;
							
							if(($chars_for_print[5] eq '!') or ($chars_for_print[6] eq '!'))
							{
								push(@chars_for_print, $pileUpString);
							}
						}
						print {$output_fh} join("\t", @chars_for_print), "\n";
					}	
				}
				
				foreach my $readID (keys %readIDs)
				{
					print {$output_fh} $readIDs{$readID}, "\t", $readID, "\n";
				}
				close($output_fh);					
			}
		}
		
		if($T == 0)
		{
			my $totalAlleles = 0;
			
			my $calibration_file = 'temp/calibration_' . $locus . '_' . $sample_IDs_abbr . '.txt';	
			open(CALIBRATION, ">", $calibration_file) or die "Cannot open $calibration_file";
			print CALIBRATION join("\t", qw/Bin MeanPP PercCorrect NCorrect NIncorrect/), "\n";
			for(my $i = 0; $i <= 9; $i++)
			{
				my $meanPP = 0;
				my $percCorrect = 0;
				
				my $nCorrect = 0;
				my $nIncorrect = 0;
				
				my $mean_normalize = 0;
				foreach my $elem (@{$calibration_baskets{$i}{correct}})			
				{
					$nCorrect += $elem->{weight};
					$meanPP += $elem->{PP}*$elem->{weight};
					$mean_normalize += $elem->{weight};
				}
				foreach my $elem (@{$calibration_baskets{$i}{incorrect}})			
				{
					$nIncorrect += $elem->{weight};
					$meanPP += $elem->{PP}*$elem->{weight};
					$mean_normalize += $elem->{weight};				
				}			
				
				if(($nCorrect+$nIncorrect) != 0)
				{
					$percCorrect = $nCorrect/($nCorrect+$nIncorrect);
				}
				
				if($mean_normalize != 0)
				{
					$meanPP = $meanPP / $mean_normalize;
				}
				
				print CALIBRATION join("\t",
					$i,
					sprintf("%.2f", $meanPP),
					sprintf("%.2f", $percCorrect),
					sprintf("%.2f", $nCorrect),
					sprintf("%.2f", $nIncorrect),
				), "\n";
				
				$totalAlleles += ($nCorrect + $nIncorrect);
			}
			close(CALIBRATION);		
			
			die "Problem $totalAlleles vs $imputed_HLA_Calls{$locus}{called}" unless($totalAlleles == $imputed_HLA_Calls{$locus}{called});
					
			my $spatial_coverage_file = 'temp/spatialCoverage_' . $locus . '_' . $sample_IDs_abbr . '.txt';	
			open(SPATIALCOVERAGE, ">", $spatial_coverage_file) or die "Cannot open $spatial_coverage_file";			
			foreach my $exon (sort {$a <=> $b} keys %coverage_over_samples)
			{
				foreach my $exonPos (sort {$a <=> $b} keys %{$coverage_over_samples{$exon}})
				{
					my @individualValues = @{$coverage_over_samples_individualValues{$exon}{$exonPos}};
					@individualValues = sort {$a <=> $b} @individualValues;
					my $idx_10 = int($#individualValues * 0.1 + 0.5);
					my $idx_90 = int($#individualValues * 0.9 + 0.5);
					print SPATIALCOVERAGE join("\t", $exon, $exonPos, $exon . '-' . $exonPos, $coverage_over_samples{$exon}{$exonPos} / $coverage_over_samples_nSamples, $individualValues[$idx_10], $individualValues[$idx_90]), "\n";
				}
			}				
			close(SPATIALCOVERAGE)		
		}
				
		my $CR = sprintf("%.2f", $imputed_HLA_Calls{$locus}{sum} ? ($imputed_HLA_Calls{$locus}{called}/$imputed_HLA_Calls{$locus}{sum}) : 0);
		my $accuracy = sprintf("%.2f", 1 - (($problem_locus_examined{$locus} != 0) ? $problem_locus_detail{$locus}/$problem_locus_examined{$locus} : 0));
				
		print SUMMARY "\t", join("\t", $locus, $problem_locus_examined{$locus}, $CR, $accuracy), "\n";
	}
	
	my $comparions_OK = $comparisons - $compare_problems;
	print "\nComparisons: $comparisons -- OK: $comparions_OK\n";
		
	if($fromMHCPRG)
	{
		open(PROBLEMSPERSAMPLE, '>>', '_problems_per_sample_running.txt') or die;
		foreach my $indivID (keys %errors_per_sample)
		{
			my $fullSampleID = $sample_noI_toI{$indivID};
			die unless(defined $fullSampleID);
			
			my $sample_dir = catfile($output_dir, "hla", $fullSampleID);
			my $aligned_file = $sample_dir.'/reads.p.n.aligned';
			die "Aligned reads file $aligned_file not existing" unless(-e $aligned_file);
			open(ALIGNED, '<', $aligned_file) or die;
			my $firstLine = <ALIGNED>;
			chomp($firstLine);
			close(ALIGNED);
			my @IS = split(/ /, $firstLine);
			die unless(scalar(@IS) == 3);
			my $effectiveReadLength = inferReadLength($aligned_file);
			my $averageAlignmentOK = averageFractionAlignmentOK($sample_dir);
			print PROBLEMSPERSAMPLE join("\t", $fullSampleID, $vP, $validated_per_sample{$indivID}, $errors_per_sample{$indivID}, $IS[1], $IS[2], $effectiveReadLength, $averageAlignmentOK), "\n";
		}
		close(PROBLEMSPERSAMPLE);
	}
	open(TMP_OUTPUT, '>', catfile($output_dir, "hla_validation", "validation_summary.txt")) or die;
	print "\nPER-LOCUS SUMMARY:\n";
	foreach my $key (sort keys %problem_locus_detail)
	{
		my $OK_locus = $problem_locus_examined{$key} - $problem_locus_detail{$key};
		my $accuracy = sprintf("%.2f", 1 - (($problem_locus_examined{$key} != 0) ? $problem_locus_detail{$key}/$problem_locus_examined{$key} : 0));
		my $CR = sprintf("%.2f", $imputed_HLA_Calls{$key}{sum} ? ($imputed_HLA_Calls{$key}{called}/$imputed_HLA_Calls{$key}{sum}) : 0);
		print "\t", $key, ": ", $OK_locus, " of ", $problem_locus_examined{$key}, ",\tAccuracy ", $accuracy, " ";
		print "\tCall rate: ", $CR,  "\n";
		
		my @fields = ($key, $problem_locus_examined{$key}, $CR, $accuracy);
		print TMP_OUTPUT join("\t", @fields), "\n";
	
	}
	close(TMP_OUTPUT);	
		
	print "\nCorrect vs incorrect coverages per locus:\n";
	foreach my $locus (sort keys %problem_locus_detail)
	{
		my @avg_minMax_ok = min_avg_max(@{$locus_avgCoverages{$locus}{ok}});
		my @low_minMax_ok = min_avg_max(@{$locus_lowCoverages{$locus}{ok}});
		my @min_minMax_ok = min_avg_max(@{$locus_minCoverages{$locus}{ok}});
			
		my @avg_minMax_problems = min_avg_max(@{$locus_avgCoverages{$locus}{problems}});
		my @low_minMax_problems = min_avg_max(@{$locus_lowCoverages{$locus}{problems}});
		my @min_minMax_problems = min_avg_max(@{$locus_minCoverages{$locus}{problems}});
		
		print "\t", $locus, "\n";

		print "\t\tAverage ", join(' / ', @avg_minMax_ok), " vs ", join(' / ', @avg_minMax_problems), " [problems]", "\n";
		print "\t\tLow ", join(' / ', @low_minMax_ok), " vs ", join(' / ', @low_minMax_problems), " [problems]", "\n";
		print "\t\tMin ", join(' / ', @min_minMax_ok), " vs ", join(' / ', @min_minMax_problems), " [problems]", "\n";
	}
	
	print "\n";
	close(SUMMARY);
	
	print "Over all loci, all individuals:\n";
	my @avg_avg_minMax = min_avg_max(@allLoci_allIndivs_avgCoverage);
	print "\tAverage ", join(' / ', @avg_avg_minMax), "\n";
	print "\tLow ", join(' / ', @avg_avg_minMax), "\n";
	print "\tMin ", join(' / ', @avg_avg_minMax), "\n";
	
	if(scalar(keys %missing_reference_data))
	{
		print "Missing reference data for individuals:\n";
		foreach my $indivID (keys %missing_reference_data)
		{
			print " - ", $indivID, "\n";
		}
	}
	
	my $vPForFile = $vP;
	if($vPForFile)
	{
		$vPForFile .= '_';
	}
	open(TYPES, '>', '_' . $vPForFile . 'types_as_validated.txt') or die;
	my %perLocus_hom_het_missing;
	my @loci_for_print = sort {$a cmp $b} (keys %problem_locus_detail);
	print TYPES join("\t", 'IndividualID', map {'HLA' . $_ } @loci_for_print), "\n";
	foreach my $indivID (sort keys %types_as_validated)
	{
		my @fields_for_indiv = ($indivID);
		foreach my $locus (@loci_for_print)
		{
			my $locus_values;
			
			if((exists $types_as_validated{$indivID}{$locus}) and (scalar(@{$types_as_validated{$indivID}{$locus}}) > 0) )
			{
				my @alleles = @{$types_as_validated{$indivID}{$locus}};
				my @alleles_for_print;
				foreach my $allele (@alleles)
				{
					if($allele =~ /\:/)
					{
						push(@alleles_for_print, $allele);
					}
					else
					{
						die unless((length($allele) == 4) or (length($allele) == 5));
						$allele =~ s/g/G/;
						$allele = substr($allele, 0, 2) . ':' . substr($allele, 2);
						push(@alleles_for_print, $allele);

					}
				}
				$locus_values = join("/", @alleles_for_print);
				
				die unless($#alleles_for_print == 1);
				if($alleles_for_print[0] eq $alleles_for_print[1])
				{
					$perLocus_hom_het_missing{$locus}[0]++;
				}
				else
				{
					$perLocus_hom_het_missing{$locus}[1]++;			
				}
			}
			else
			{
				$locus_values = '????/????';
				$perLocus_hom_het_missing{$locus}[2]++;
			}
			
			die unless(defined $locus_values);
			
			push(@fields_for_indiv, $locus_values);
			
		}
		print TYPES join("\t", @fields_for_indiv), "\n";
	}
	close(TYPES);
	
	open(HOMHET, '>', '_' . $vPForFile . 'types_as_validated_homhet.txt') or die;
	print HOMHET join("\t", qw/Locus Hom Het HomMissing/), "\n";
	foreach my $locus (keys %perLocus_hom_het_missing)
	{
		my @printFields = ($locus);
		for(my $i = 0; $i <= 2; $i++)
		{
			my $v = 0;
			if(defined $perLocus_hom_het_missing{$locus}[$i])
			{
				$v = $perLocus_hom_het_missing{$locus}[$i];
			}
			push(@printFields, $v);
		}
		print HOMHET join("\t", @printFields), "\n";
	}
	close(HOMHET)
	
}


if($actions =~ /w/)
{
	my $validation_round = 'R2';
	die "Please specify --trueHaplotypes for validation" unless($trueHaplotypes);
	
	my $debug = 0;
	
	# read reference dataset
	my %reference_data;
	open(REFERENCE, "<", $trueHaplotypes) or die "Cannot open $trueHaplotypes";
	my $headerLine = <REFERENCE>;
	chomp($headerLine);
	$headerLine =~ s/\n//g;
	$headerLine =~ s/\r//g;
	my @header_fields = split(/\t/, $headerLine);
	@header_fields = map {if($_ =~ /HLAD((QA)|(QB)|(RB))$/){$_ .= '1';} $_} @header_fields;	
	while(<REFERENCE>)
	{
		my $line = $_;
		chomp($line);
		
		$line =~ s/\n//g;
		$line =~ s/\r//g;
		
		my @fields = split(/\t/, $line);
		my %line = (mesh @header_fields, @fields);
		
		my $primary_key = $line{'IndividualID'};
		$reference_data{$primary_key} = \%line;
	}
	close(REFERENCE);
	
	# perturbed positions
	my %reference_data_perturbedWhere;	
	my $trueHaplotypes_perturbed = $trueHaplotypes . '.perturbed';
	if(-e $trueHaplotypes_perturbed)
	{
		open(REFERENCE, "<", $trueHaplotypes_perturbed) or die "Cannot open $trueHaplotypes_perturbed";
		my $headerLine = <REFERENCE>;
		chomp($headerLine);
		$headerLine =~ s/\n//g;
		$headerLine =~ s/\r//g;
		my @header_fields = split(/\t/, $headerLine);
		@header_fields = map {if($_ =~ /HLAD((QA)|(QB)|(RB))$/){$_ .= '1';} $_} @header_fields;	
		while(<REFERENCE>)
		{
			my $line = $_;
			chomp($line);
			
			$line =~ s/\n//g;
			$line =~ s/\r//g;
			
			my @fields = split(/\t/, $line);
			my %line = (mesh @header_fields, @fields);
			
			my $primary_key = $line{'IndividualID'};
			$reference_data_perturbedWhere{$primary_key} = \%line;
		}
		close(REFERENCE);
	}
	else
	{
		warn "No perturbation information ($trueHaplotypes_perturbed) found.";
	}	
	
	
	my %imputed_haplotypes;
	my %sample_noI_toI;
	
	my %imputed_haplotypes_lines;
	
	$debug = 1;
	
	foreach my $sampleID (@sampleIDs) 
	{
		my $sampleID_noI = $sampleID;
		$sampleID_noI =~ s/^I\d+_//g;
		
		my @bestGuess_files = glob( catfile($output_dir, "hla", $sampleID, $validation_round.'_haplotypes_bestguess_*.txt'));
		
		foreach my $bestGuess_file (@bestGuess_files)
		{
			die unless($bestGuess_file =~ /haplotypes_bestguess_(.+)\.txt/);
			my $locus = $1;
			
			# next unless($locus eq 'A'); # todo remove   
			
			unless(-e $bestGuess_file)
			{
				warn "Best-guess file $bestGuess_file not existing";
				next;
			}		
			  
			open(BESTGUESS, '<', $bestGuess_file) or die "Cannot open $bestGuess_file";
			my @bestguess_header_fields = qw/Position GraphLevel Type TypeNumber PositionInType C1 C2 GTConfidence PruningInterval PruningC1 PruningC1HaploConfidence PruningC2 PruningC2HaploConfidence NReads ReadAlleles ConsideredGTPairs ConsideredH1 ConsideredH2 AA1 AA1HaploConf AA2 AA2HaploConf/;
			while(<BESTGUESS>)
			{
				my $line = $_;
				chomp($line);
				my @line_fields = split(/\t/, $line, -1);
				die Dumper("Line fields problem", $#line_fields, $#bestguess_header_fields) unless($#line_fields == $#bestguess_header_fields);
				my %line_hash = (mesh @bestguess_header_fields, @line_fields);
				
				my $Q = $line_hash{'GTConfidence'};
				if($Q < $T)
				{
					$imputed_haplotypes{$locus}{$sampleID_noI}[0] .= '?;';	
					$imputed_haplotypes{$locus}{$sampleID_noI}[1] .= '?;';	
				}
				else
				{
					$imputed_haplotypes{$locus}{$sampleID_noI}[0] .= $line_hash{'C1'}.';';	
					$imputed_haplotypes{$locus}{$sampleID_noI}[1] .= $line_hash{'C2'}.';';
				}
				
				if($debug)
				{
					push(@{$imputed_haplotypes_lines{$locus}{$sampleID_noI}}, $line);
				}
			}	
			close(BESTGUESS);
			
			die if((exists $sample_noI_toI{$sampleID_noI}) and ($sample_noI_toI{$sampleID_noI} ne $sampleID));
			$sample_noI_toI{$sampleID_noI} = $sampleID;
		}
	}
		
	my @loci = sort keys %imputed_haplotypes;
	
	my $process_quality_measures = sub {};
	
	
	foreach my $locus (@loci)
	{
		my $arbitraty_indiv = (keys %reference_data)[0];
		next unless((defined $reference_data{$arbitraty_indiv}{'HLA'.$locus}));
		
		my $locus_agree = 0;
		my $locus_disagree = 0;
		my $locus_missing = 0;

		my $locus_gt_agree = 0;
		my $locus_gt_disagree = 0;
		my $locus_gt_missing = 0;
					
		my $locus_pt_agree = 0;
		my $locus_pt_disagree = 0;
		my $locus_pt_missing = 0;

		my $locus_pt_gt_agree = 0;
		my $locus_pt_gt_disagree = 0;
		my $locus_pt_gt_missing = 0;
		
		my @indivIDs = keys %{$imputed_haplotypes{$locus}};
		INDIV: foreach my $indivID (@indivIDs)
		{	
			$debug = 0;
			
			# my @imputed_hla_values = map { $imputed_HLA{$locus}{$indivID}{$_} } keys %{$imputed_HLA{$locus}{$indivID}};
			my @imputed_haplotypes = @{ $imputed_haplotypes{$locus}{$indivID} };
								
			next INDIV unless($#imputed_haplotypes == 1);
			next INDIV unless(exists $reference_data{$indivID});
			next INDIV unless(exists $reference_data{$indivID}{'HLA'.$locus});
			
			$reference_data{$indivID}{'HLA'.$locus} or die;
			
			my @reference_haplotypes = split(/\//, $reference_data{$indivID}{'HLA'.$locus});
			if(not $reference_data_perturbedWhere{$indivID}{'HLA'.$locus})
			{
				warn "No reference haplotype for $locus";
				$reference_data_perturbedWhere{$indivID}{'HLA'.$locus} = '';
			}
			my @reference_haplotypes_perturbed = split(/\//, $reference_data_perturbedWhere{$indivID}{'HLA'.$locus});
			
			die Dumper($reference_data{$indivID}, \@reference_haplotypes) unless($#reference_haplotypes == 1);
				
			die unless($#imputed_haplotypes == 1);
			die unless($#reference_haplotypes == 1);
			
			my @reference_haplotypes_split = (map {[split(/;/, $_)]} @reference_haplotypes);
			my @reference_haplotypes_perturbed_split = (map {split(/;/, $_)} @reference_haplotypes_perturbed);
			
			my %perturbedWhere = map {$_ => 1} @reference_haplotypes_perturbed_split;
			
			# die Dumper(\%perturbedWhere);

			my @imputed_haplotypes_split = (map {[split(/;/, $_)]} @imputed_haplotypes);
			
			die unless($#reference_haplotypes_split == 1);
			die unless($#imputed_haplotypes_split == 1);
			
			die Dumper($#reference_haplotypes_split, $#imputed_haplotypes_split, [$#{$reference_haplotypes_split[0]}, $#{$reference_haplotypes_split[1]}], [$#{$imputed_haplotypes_split[0]}, $#{$imputed_haplotypes_split[1]}]) unless($#{$reference_haplotypes_split[0]} == $#{$reference_haplotypes_split[1]});
			
			die Dumper($#reference_haplotypes_split, $#imputed_haplotypes_split, [$#{$reference_haplotypes_split[0]}, $#{$reference_haplotypes_split[1]}], [$#{$imputed_haplotypes_split[0]}, $#{$imputed_haplotypes_split[1]}]) unless($#{$imputed_haplotypes_split[0]} == $#{$imputed_haplotypes_split[1]});

			die Dumper($#reference_haplotypes_split, $#imputed_haplotypes_split, [$#{$reference_haplotypes_split[0]}, $#{$reference_haplotypes_split[1]}], [$#{$imputed_haplotypes_split[0]}, $#{$imputed_haplotypes_split[1]}]) unless($#{$reference_haplotypes_split[0]} == $#{$imputed_haplotypes_split[1]});
			
			my @alleles_agree = (0, 0);
			my @alleles_missing = (0, 0);;
			my @alleles_disagree = (0, 0);;

			my @alleles_gt_agree = (0, 0);
			my @alleles_gt_missing = (0, 0);;
			my @alleles_gt_disagree = (0, 0);;
			
			my @alleles_pt_agree = (0, 0);
			my @alleles_pt_missing = (0, 0);;
			my @alleles_pt_disagree = (0, 0);;

			my @alleles_pt_gt_agree = (0, 0);
			my @alleles_pt_gt_missing = (0, 0);;
			my @alleles_pt_gt_disagree = (0, 0);;
			
			
			for(my $invertImputations = 0; $invertImputations <= 1; $invertImputations++)
			{
				my @imputed_haplotypes_split_forAnalysis = ($invertImputations) ? reverse(@imputed_haplotypes_split) : @imputed_haplotypes_split;
				
				for(my $i = 0; $i <= $#{$reference_haplotypes_split[0]}; $i++)
				{
					for(my $j = 0; $j <= 1; $j++)
					{
						die unless((defined $reference_haplotypes_split[$j][$i]) and (defined $imputed_haplotypes_split_forAnalysis[$j][$i]));
						if($imputed_haplotypes_split_forAnalysis[$j][$i] eq "?")
						{
							$alleles_missing[$invertImputations]++;
							if($perturbedWhere{$i})
							{
								$alleles_pt_missing[$invertImputations]++;
							}
						}
						else
						{
							if($reference_haplotypes_split[$j][$i] eq $imputed_haplotypes_split_forAnalysis[$j][$i])
							{
								$alleles_agree[$invertImputations]++;
								if($perturbedWhere{$i})
								{
									$alleles_pt_agree[$invertImputations]++;
								}								
							}
							else
							{
								$alleles_disagree[$invertImputations]++;
								if($perturbedWhere{$i})
								{
									$alleles_pt_disagree[$invertImputations]++;
								}									
							}
						}
					}
					
					my ($thisPosition_gt_agree, $thisPosition_gt_disagree, $thisPosition_gt_missing) = compatibleStringAlleles([$reference_haplotypes_split[0][$i], $reference_haplotypes_split[1][$i]], [$imputed_haplotypes_split_forAnalysis[0][$i], $imputed_haplotypes_split_forAnalysis[1][$i]]);
					
					$alleles_gt_agree[$invertImputations] += $thisPosition_gt_agree;
					$alleles_gt_disagree[$invertImputations] += $thisPosition_gt_disagree;
					$alleles_gt_missing[$invertImputations] += $thisPosition_gt_missing;
					
					if($perturbedWhere{$i})
					{					
						$alleles_pt_gt_agree[$invertImputations] += $thisPosition_gt_agree;
						$alleles_pt_gt_disagree[$invertImputations] += $thisPosition_gt_disagree;
						$alleles_pt_gt_missing[$invertImputations] += $thisPosition_gt_missing;
					
						if(($invertImputations == 0) and ($thisPosition_gt_agree != 2) and 0)
						{
							print "Position $i -- agreement: $thisPosition_gt_agree\n";
							print "\tTrue genotypes: ", join('/', $reference_haplotypes_split[0][$i], $reference_haplotypes_split[1][$i]), "\n";
							print "\tImputed genotypes: ", join('/', $imputed_haplotypes_split_forAnalysis[0][$i], $imputed_haplotypes_split_forAnalysis[1][$i]), "\n";
							print "\t\tLine: ",	$imputed_haplotypes_lines{$locus}{$indivID}[$i], "\n";
							print "\n";
						}					
					}
					
					if(($invertImputations == 0) and ($thisPosition_gt_agree != 2))
					{
						# print "Position $i -- agreement: $thisPosition_gt_agree\n";
						# print "\tTrue genotypes: ", join('/', $reference_haplotypes_split[0][$i], $reference_haplotypes_split[1][$i]), "\n";
						# print "\tImputed genotypes: ", join('/', $imputed_haplotypes_split_forAnalysis[0][$i], $imputed_haplotypes_split_forAnalysis[1][$i]), "\n";
						# print "\t\tLine: ",	$imputed_haplotypes_lines{$locus}{$indivID}[$i], "\n";
						# print "\n";
					}
				}
			}
			
			die unless($alleles_gt_agree[0] == $alleles_gt_agree[1]);
			die unless($alleles_gt_disagree[0] == $alleles_gt_disagree[1]);
			die unless($alleles_gt_missing[0] == $alleles_gt_missing[1]);
			
			# print "Individual $indivID Locus $locus\n";
			my @invertImputations_notOK;
			for(my $invertImputations = 0; $invertImputations <= 1; $invertImputations++)
			{	
				my $alleles_sum = $alleles_agree[$invertImputations] + $alleles_disagree[$invertImputations] + $alleles_missing[$invertImputations];
				die unless($alleles_sum > 0);
				
				# print "\t", "Inversion ", $invertImputations, "\n";
				# print "\t\tOK:       ", $alleles_agree[$invertImputations], " ", sprintf("%.2f", $alleles_agree[$invertImputations]/$alleles_sum * 100), "%\n";
				# print "\t\tNOT OK:   ", $alleles_disagree[$invertImputations], " ", sprintf("%.2f", $alleles_disagree[$invertImputations]/$alleles_sum * 100), "%\n";
				# print "\t\tMISSING:  ", $alleles_missing[$invertImputations], " ", sprintf("%.2f", $alleles_missing[$invertImputations]/$alleles_sum * 100), "%\n";
				# print "\n";
				
				$invertImputations_notOK[$invertImputations] = $alleles_disagree[$invertImputations];
				
				my $alleles_pt_sum = $alleles_pt_agree[$invertImputations] + $alleles_pt_disagree[$invertImputations] + $alleles_pt_missing[$invertImputations];
				
				# print "\t", "Inversion ", $invertImputations, " (perturbed alleles only)\n";
				# if($alleles_pt_sum > 0)		
				# {
					# print "\t\tOK:       ", $alleles_pt_agree[$invertImputations], " ", sprintf("%.2f", $alleles_pt_agree[$invertImputations]/$alleles_pt_sum * 100), "%\n";
					# print "\t\tNOT OK:   ", $alleles_pt_disagree[$invertImputations], " ", sprintf("%.2f", $alleles_pt_disagree[$invertImputations]/$alleles_pt_sum * 100), "%\n";
					# print "\t\tMISSING:  ", $alleles_pt_missing[$invertImputations], " ", sprintf("%.2f", $alleles_pt_missing[$invertImputations]/$alleles_pt_sum * 100), "%\n";
				# }
				# print "\n";
				
			}
			
			my $invertImputations_optimal = ($invertImputations_notOK[1] < $invertImputations_notOK[0]) ? 1 : 0;
			
			my $alleles_sum = $alleles_agree[$invertImputations_optimal] + $alleles_disagree[$invertImputations_optimal] + $alleles_missing[$invertImputations_optimal];
			die unless($alleles_sum > 0);
						
			
			# print "\t", "Haplotypes - inverted ", $invertImputations_optimal, "\n";
			# print "\t\tOK:       ", $alleles_agree[$invertImputations_optimal], " ", sprintf("%.2f", $alleles_agree[$invertImputations_optimal]/$alleles_sum * 100), "%\n";
			# print "\t\tNOT OK:   ", $alleles_disagree[$invertImputations_optimal], " ", sprintf("%.2f", $alleles_disagree[$invertImputations_optimal]/$alleles_sum * 100), "%\n";
			# print "\t\tMISSING:  ", $alleles_missing[$invertImputations_optimal], " ", sprintf("%.2f", $alleles_missing[$invertImputations_optimal]/$alleles_sum * 100), "%\n";
			# print "\n";
				
			
			my $alleles_gt_sum = $alleles_gt_agree[0] + $alleles_gt_disagree[0] + $alleles_gt_missing[0];
			# print "\t", "Genotypes ", "\n";
			# print "\t\tOK:       ", $alleles_gt_agree[0], " ", sprintf("%.2f", $alleles_gt_agree[0]/$alleles_gt_sum * 100), "%\n";
			# print "\t\tNOT OK:   ", $alleles_gt_disagree[0], " ", sprintf("%.2f", $alleles_gt_disagree[0]/$alleles_gt_sum * 100), "%\n";
			# print "\t\tMISSING:  ", $alleles_gt_missing[0], " ", sprintf("%.2f", $alleles_gt_missing[0]/$alleles_gt_sum * 100), "%\n";
			# print "\n";			
			
			my $alleles_pt_gt_sum = $alleles_pt_gt_agree[0] + $alleles_pt_gt_disagree[0] + $alleles_pt_gt_missing[0];
			# print "\t", "Genotypes at perturbed positions", "\n";
			# if($alleles_pt_gt_sum > 0)
			# {
				# print "\t\tOK:       ", $alleles_pt_gt_agree[0], " ", sprintf("%.2f", $alleles_pt_gt_agree[0]/$alleles_pt_gt_sum * 100), "%\n";
				# print "\t\tNOT OK:   ", $alleles_pt_gt_disagree[0], " ", sprintf("%.2f", $alleles_pt_gt_disagree[0]/$alleles_pt_gt_sum * 100), "%\n";
				# print "\t\tMISSING:  ", $alleles_pt_gt_missing[0], " ", sprintf("%.2f", $alleles_pt_gt_missing[0]/$alleles_pt_gt_sum * 100), "%\n";
			# }
			# print "\n";					
								
			$locus_agree += $alleles_agree[$invertImputations_optimal];
			$locus_disagree += $alleles_disagree[$invertImputations_optimal];
			$locus_missing += $alleles_missing[$invertImputations_optimal];
			
			$locus_gt_agree += $alleles_gt_agree[0];
			$locus_gt_disagree += $alleles_gt_disagree[0];
			$locus_gt_missing += $alleles_gt_missing[0];	

			$locus_pt_agree += $alleles_pt_agree[$invertImputations_optimal];
			$locus_pt_disagree += $alleles_pt_disagree[$invertImputations_optimal];
			$locus_pt_missing += $alleles_pt_missing[$invertImputations_optimal];
			
			$locus_pt_gt_agree += $alleles_pt_gt_agree[0];
			$locus_pt_gt_disagree += $alleles_pt_gt_disagree[0];
			$locus_pt_gt_missing += $alleles_pt_gt_missing[0];	
		}
		
		my $locus_sum = $locus_agree + $locus_disagree + $locus_missing;
		my $locus_gt_sum = $locus_gt_agree + $locus_gt_disagree + $locus_gt_missing;
		
		die if($locus_sum == 0);
		print "LOCUS SUMMARY $locus\n";
		print "\tHaplotypes:\n";
		print "\t\tOK:       ", $locus_agree, " ", sprintf("%.2f", $locus_agree/$locus_sum * 100), "%\n";
		print "\t\tNOT OK:   ", $locus_disagree, " ", sprintf("%.2f", $locus_disagree/$locus_sum * 100), "%\n";
		print "\t\tMISSING:  ", $locus_missing, " ", sprintf("%.2f", $locus_missing/$locus_sum * 100), "%\n\n";
		print "\tGenotypes:\n";
		print "\t\tOK:       ", $locus_gt_agree, " ", sprintf("%.2f", $locus_gt_agree/$locus_gt_sum * 100), "%\n";
		print "\t\tNOT OK:   ", $locus_gt_disagree, " ", sprintf("%.2f", $locus_gt_disagree/$locus_gt_sum * 100), "%\n";
		print "\t\tMISSING:  ", $locus_gt_missing, " ", sprintf("%.2f", $locus_gt_missing/$locus_gt_sum * 100), "%\n";
		print "\n";
		
		my $locus_pt_sum = $locus_pt_agree + $locus_pt_disagree + $locus_pt_missing;
		my $locus_pt_gt_sum = $locus_pt_gt_agree + $locus_pt_gt_disagree + $locus_pt_gt_missing;
		
		print "LOCUS SUMMARY $locus (perturbed only)\n";
		if($locus_pt_sum > 0)
		{
			print "\tHaplotypes:\n";
			print "\t\tOK:       ", $locus_pt_agree, " ", sprintf("%.2f", $locus_pt_agree/$locus_pt_sum * 100), "%\n";
			print "\t\tNOT OK:   ", $locus_pt_disagree, " ", sprintf("%.2f", $locus_pt_disagree/$locus_pt_sum * 100), "%\n";
			print "\t\tMISSING:  ", $locus_pt_missing, " ", sprintf("%.2f", $locus_pt_missing/$locus_pt_sum * 100), "%\n\n";
			print "\tGenotypes:\n";
			print "\t\tOK:       ", $locus_pt_gt_agree, " ", sprintf("%.2f", $locus_pt_gt_agree/$locus_pt_gt_sum * 100), "%\n";
			print "\t\tNOT OK:   ", $locus_pt_gt_disagree, " ", sprintf("%.2f", $locus_pt_gt_disagree/$locus_pt_gt_sum * 100), "%\n";
			print "\t\tMISSING:  ", $locus_pt_gt_missing, " ", sprintf("%.2f", $locus_pt_gt_missing/$locus_pt_gt_sum * 100), "%\n";
		}	
	
		# exit; # todo remove
	}

	# my $comparions_OK = $comparisons - $compare_problems;
	# print "\nComparisons: $comparisons -- OK: $comparions_OK\n";
		
	open(TMP_OUTPUT, '>', catfile($output_dir, "hla_validation","validation_haplotypes_summary.txt")) or die;
	# print "\nPER-LOCUS SUMMARY:\n";
	# foreach my $key (sort keys %problem_locus_detail)
	# {
		# my $OK_locus = $problem_locus_examined{$key} - $problem_locus_detail{$key};
		# my $accuracy = sprintf("%.2f", 1 - (($problem_locus_examined{$key} != 0) ? $problem_locus_detail{$key}/$problem_locus_examined{$key} : 0));
		# my $CR = sprintf("%.2f", $imputed_HLA_Calls{$key}{sum} ? ($imputed_HLA_Calls{$key}{called}/$imputed_HLA_Calls{$key}{sum}) : 0);
		# print "\t", $key, ": ", $OK_locus, " of ", $problem_locus_examined{$key}, ",\tAccuracy ", $accuracy, " ";
		# print "\tCall rate: ", $CR,  "\n";
		
		# my @fields = ($key, $problem_locus_examined{$key}, $CR, $accuracy);
		# print TMP_OUTPUT join("\t", @fields), "\n";
	# }
	close(TMP_OUTPUT);	

	print "\n";
}


sub test_if_file_exists {  
  my ($file) = @_; 
  unless(-e $file ) {
    die "Expected file $file not found";
  } 
}


sub check_input { 
  my ($output_dir, $hla_nom_dir, $graph_root_dir) = @_; 

  if ( !defined $output_dir ) { 
    die("Please use option --output_dir to specify a location for the output files\n"); 
  } 
  if ( !defined $hla_nom_dir ) { 
    die("Please use option --hla_nom_dir to specify the location of the hla nomenclature file\n"); 
  } 
  if ( !defined $graph_root_dir ) {  
    die("Please use option --graph_root_dir to specify the location of the graph files\n"); 
  }  
} 
