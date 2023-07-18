#!/usr/bin/perl -w

use strict;
use Getopt::Long;
use File::Basename;
use File::Path;
use FileHandle;
use Geo::GDAL;
use Geo::Proj4;
use Math::Trig qw/pi/;
use PDL;
use PDL::NetCDF;
use PDL::NiceSlice;
use PDL::IO::FlexRaw;
use Fcntl;
use POSIX qw/tmpnam/;
use RIMS;		### WSAG UNH module

			### pdl_wbm_io.pl must be in the same directory
my  $script_dir = '/net/nfs/zero/home/WBM_TrANS/';
# my  $script_dir = '/net/home/cv/alexp/perl/wbm/';
my ($init_file, $io_file)	= ($script_dir.'pdl_wbm_path.init', $script_dir.'pdl_wbm_io.pl');
{			### pdl_wbm_io.pl must be in the same directory
  local @ARGV	= ($init_file);
  require $io_file;
}			### pdl_wbm_path.init must be in the same directory

use vars qw(*OLDERR);		# To avoid silly warning messages from GDAL, such as
open OLDERR, ">&STDERR";	# "No UNIDATA NC_GLOBAL:Conventions attribute"

#######################################################################
##################     Initializations      ###########################

my $test_dir	= '/net/nfs/ipswich/raid/atlas/data/gdal_test_files';
my @coord	= (-71.0, 47.5);

my $file_g1	= "NETCDF:$test_dir/MERRA.prod.assim.tavg1_2d_slv_Nx.19790101.SUB.nc:t2m";	# Good # 1
my $file_b1	= "NETCDF:$test_dir/wrfout_d03_T2_2006-02-01.nc:T2";				# Bad  # 1
my $file_b2	= "NETCDF:$test_dir/air.2m.1948.nc:air";					# Bad  # 2

			### Generic dataset metadata
my $meta_g1	= {'Var_Scale' => 1, 'Var_Offset' => -273.15,'Processing' => '', 'Projection' => 'epsg:4326'};
my $meta_b1	= {'Var_Scale' => 1, 'Var_Offset' => 0,      'Processing' => '', 'Projection' => 'epsg:8001'};
my $meta_b2	= {'Var_Scale' => 1, 'Var_Offset' => -273.15,'Processing' => '', 'Projection' => 'epsg:4326'};

#######################################################################
##################     Read Input Data      ###########################

my $proj_from	= Geo::Proj4->new(init => 'epsg:4326');
my $proj_to	= Geo::Proj4->new(init => 'epsg:8001');
my @coordB1	= @{$proj_from->transform($proj_to, \@coord)};

my $extent_g1	= get_extent($file_g1, $$meta_g1{Projection});
my $extent_b1	= get_extent($file_b1, $$meta_b1{Projection});
my $extent_b2	= get_extent($file_b2, $$meta_b2{Projection});

my @colRow_g1	= colRow($extent_g1, @coord);
my @colRow_b1	= colRow($extent_b1, @coordB1);
my @colRow_b2	= colRow($extent_b2, @coord);

			### Read raster
my $rData_g1	= (read_raster($file_g1)		   + $$meta_g1{Var_Offset})->setbadtoval(-100);
my $rData_b1	= (read_raster($file_b1))					   ->setbadtoval(-100);
my $rData_b2	= (read_raster($file_b2,1, [0.01, 477.65]) + $$meta_b2{Var_Offset})->setbadtoval(-100);

			### Read GDAL
my $gData_g1	= read_GDAL($extent_g1, $meta_g1, 0, $file_g1, 1, -100)->setbadtoval(-100);
my $gData_b1	= read_GDAL($extent_b1, $meta_b1, 0, $file_b1, 1, -100)->setbadtoval(-100);
my $gData_b2	= read_GDAL($extent_b2, $meta_b2, 0, $file_b2, 1, -100)->setbadtoval(-100);

#######################################################################
##################     Report Results      ############################

my $result	= (
	sprintf('%.2f',$rData_g1->at(@colRow_g1)) ==  -1.33 &&
	sprintf('%.2f',$rData_b1->at(@colRow_b1)) == -20.44 &&
	sprintf('%.2f',$rData_b2->at(@colRow_b2)) == -19.70 &&

	sprintf('%.2f',$gData_g1->at(@colRow_g1)) ==  -1.33 &&
	sprintf('%.2f',$gData_b1->at(@colRow_b1)) == -20.44 &&
	sprintf('%.2f',$gData_b2->at(@colRow_b2)) == -19.70) ? 1 : 0;

print $result ? "\n\tPassed\n" : "\n\tFailed\n";

print  "\nNo warp -\n";
printf "Good # 1: Read =%7.2f; Expected =  -1.33\n", $rData_g1->at(@colRow_g1);
printf "Bad  # 1: Read =%7.2f; Expected = -20.44\n", $rData_b1->at(@colRow_b1);
printf "Bad  # 2: Read =%7.2f; Expected = -19.70\n", $rData_b2->at(@colRow_b2);

print  "\nWith warp-\n";
printf "Good # 1: Read =%7.2f; Expected =  -1.33\n", $gData_g1->at(@colRow_g1);
printf "Bad  # 1: Read =%7.2f; Expected = -20.44\n", $gData_b1->at(@colRow_b1);
printf "Bad  # 2: Read =%7.2f; Expected = -19.70\n", $gData_b2->at(@colRow_b2);

print "\n";
close OLDERR;
exit;

#######################################################################
######################  Functions  ####################################
