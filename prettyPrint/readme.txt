The scripts under this directory will generates HTML files for each source code file and for each directory in a repository

Dependencies:
 - HTML::Template
 - DBI
Note: if there is any third party library dependency missing, install whatever the terminal reports that is missing.

How to generate views:
the build.sh will:
 - run prettyPrint to generate file views
 - run prettyPrintDirView to generate directory views

Note: Before you start running build.sh, you should go inside the build.sh and make sure the parameters to the correct path

Directory View:
to print single directory:
    prettyPrintDirView2.pl [options] [--print-single] <path> <repoDir> <cregitRepoDB> <authorsDB> <blametokensDB> <outputDir>

to recursively print directories:
prettyPrintDirView2.pl [options] --print-recursive <path> <reepoDir> <cregitRepoDB> <authorsDB> <blametokensDB> <outputDir>

to determine which directory to print or to start printing:
in the build.sh, change the DIRVIEWPATH variable to the directory you want to print or start printing