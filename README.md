# VeeamDedupeReport
total Dedupe reporting using dedupe appliance dedupe factor

slightly customized to:
Only show repositories with type "ExaGrid". 
minor fixes regarding powershell version-specific matters (string matching)

# Usage

VeeamDedupeReport.ps1 -egridDedupe 2.4 -verbose 0

verbosity options: 0(default), 1 and 2. 
1 and 2 output specific vib/vbk file dedupe details to the console where 2 will also output a csv file.
