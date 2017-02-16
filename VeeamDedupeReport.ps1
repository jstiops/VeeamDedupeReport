Param (
    [decimal]$egridDedup = 2.4,
    [int]$verbose = 0)
# Assume ExaGrid gets the above dedup if they don't specify
# Default is basic info; 1 lists each backup file with data size (what Veeam pulled), backup size (what was written to repo)
#     2 is same as 1 but lists only backup files in a csv form

if((Get-PSSnapin -Name VeeamPSSnapIn -ErrorAction SilentlyContinue) -eq $null){
    Add-PSSnapin "VeeamPSSnapIn"
}



$totalTotalBS = 0
$totalTotalDS = 0
$totalTotalCount = 0
$totalRepos = 0
$AvgIncBSTotal = 0
$AvgFullBSTotal = 0
$AvgIncDSTotal = 0
$AvgFullBSTotal = 0
$csvFilename = "C:\VeeamReports\VeeamDedupReport.csv"
$useGetStorages = 0	# 0 means not set yet; 1 means use old GetStorages() method on BU, 2 means use new GetAllStorages on BU

write-host "Combined dedup ratio (X:1) for all Veeam backups when ExaGrid dedup is",$egridDedup," Calculated using TotalDataSize/TotalBackupSize: "

Remove-Item $csvFilename -Force -ErrorAction SilentlyContinue

foreach ($repo in (Get-VBRBackupRepository | where-object {$_.Type -eq "ExaGrid"})) {
  $totalRepos = $totalRepos + 1
  $totalRepoBS = 0
  $totalRepoDS = 0
  $totalRepoCount = 0
  write-host "--------------------------------------------------------------------"
  write-host "Repository: " $repo.Name $repo.Type $repo.Path
  foreach ($bu in $repo.getBackups()) {
    if (!$bu) {
      continue
    }
    $name = $bu.JobName

    # V9 changed the method needed to get storage; figure out which one we need to use
    if ($useGetStorages -eq 0) {
       $useGetStorages = 2	# assume v9
       $members = Get-Member -InputObject $bu -membertype method
       foreach ($member in $members) {
         if ($member.Name -contains "GetStorages") {
           $useGetStorages = 1
           write-host ("Found earlier than V9")
           break
         }
       }
    }

    $jb = Get-VBRJob -Name $name
    # There may or may not be a job defined that's associated with this backup
    # Imported backups often won't have an associated job
    if ($jb) {
      $jo = $jb.Options
      $ed = $jo.BackupStorageOptions.EnableDeduplication
      $cl = $jo.BackupStorageOptions.CompressionLevel
      switch ($cl) {
       0 {$cl = "None"}
       4 {$cl = "Dedup-friendly"}
       5 {$cl = "Optimal"}
       6 {$cl = "High"}
       9 {$cl = "Extreme"}
      }
    } else {
      $ed = "<Backup deleted/imported>"
      $cl = "<Backup deleted/imported>"
    }
    write-host ("Veeam Job: $($jb.Name), ") -nonewline
    write-host ("Veeam Job Included Size (GB):","{0:N2}" -f (($jb.Info.IncludedSize)/(1000*1000*1000)) )

    $totalBS = 0
    $totalDS = 0
    $totalCount = 0
    $totalInc = 0
    $totalIncDataSize = 0
    $totalIncCount = 0
    $totalFull = 0
    $totalFullDataSize = 0
    $totalFullCount = 0
    $OutArray = @()
    if ($useGetStorages -eq 1) {
      $storages = $bu.GetStorages()
    } else {
      $storages = $bu.GetAllStorages()
    }
    foreach ($storage in $storages)
    {
      $totalCount = $totalCount + 1
      $totalTotalCount = $totalTotalCount + 1
      $totalRepoCount = $totalRepoCount + 1
      $st = $storage.Stats
      $totalBS = $totalBS + $st.BackupSize
      $totalDS = $totalDS + $st.DataSize
      $totalTotalBS = $totalTotalBS + $st.BackupSize
      $totalTotalDS = $totalTotalDS + $st.DataSize
      $totalRepoBS = $totalRepoBS + $st.BackupSize
      $totalRepoDS = $totalRepoDS + $st.DataSize
      $perfile = "" | Select "job","path","data_size","backup_size"
      $perfile.job = $($jb.Name)
      if ($storage.Info.FilePath -like "*.vib") {
         $totalIncCount = $totalIncCount + 1
         $totalInc = $totalInc + $st.BackupSize
         $perfile.backup_size = ("{0:N2}" -f $st.BackupSize)
         $totalIncDataSize = $totalIncDataSize + $st.DataSize
         $perfile.data_size = ("{0:N2}" -f $st.DataSize)
      }
      if ($storage.Info.FilePath -like "*.vbk") {
         $totalFullCount = $totalFullCount + 1
         $totalFull = $totalFull + $st.BackupSize
         $perfile.backup_size = ("{0:N2}" -f $st.BackupSize)
         $totalFullDataSize = $totalFullDataSize + $st.DataSize
         $perfile.data_size = ("{0:N2}" -f $st.DataSize)
      }
      $perfile.path = $($storage.Info.FilePath)
      if ($verbose -ge 1) {
         write-host ("    Backup: $($storage.Info.FilePath)") -nonewline
         write-host (" DataSize(VM):","{0:N2}" -f $st.DataSize) -nonewline
         write-host (" Backup Size on disk:","{0:N2}" -f $st.BackupSize) -nonewline
         write-host (" CompressRatio:","{0:N2}" -f $st.CompressRatio) -nonewline
         write-host (" CreationTime: $($storage.Info.CreationTime)")
      }
      $OutArray += ,$perfile
    }		# foreach storage (backup file)

    if ($jb) {
        write-host ("    Associated job's Compression level:",$cl,", Dedup enabled:",$ed,", Retain cycles/days:",$jo.BackupStorageOptions.RetainCycles,"/",$jo.BackupStorageOptions.RetainDays)
    }

    if ($totalIncCount -gt 0) {
      write-host ("    Incremental: Count:", $totalIncCount) -nonewline
      $avg = $totalIncDataSize/($totalIncCount*1000*1000*1000)
      write-host ("  Avg Incremental Data (VM) Size on disk (GB):","{0:N2}" -f ($avg)) -nonewline
      $perfile = "" | Select "job","path","data_size","backup_size"
      $perfile.job = $($jb.Name)
      $perfile.path = "Incremental Avg Data (VM) Size (GB)"
      $perfile.data_size = ("{0:N2}" -f $avg)
      $OutArray += ,$perfile

      # Keep a running total of avg sizes across jobs
      $AvgIncDSTotal += $avg

      $avg = $totalInc/($totalIncCount*1000*1000*1000)
      write-host ("  Avg Incremental Backup Size on disk (GB):","{0:N2}" -f ($avg))
      $perfile = "" | Select "job","path","data_size","backup_size"
      $perfile.job = $($jb.Name)
      $perfile.path = "Incremental Avg Backup Size on disk (GB)"
      $perfile.backup_size = ("{0:N2}" -f $avg)
      $OutArray += ,$perfile

      # Keep a running total of avg sizes across jobs
      $AvgIncBSTotal += $avg
    } else {
      write-host ("    No Incremental Backups for this job in this repository.")
    }

    if ($totalFullCount -gt 0) {
      write-host ("    Full: Count:", $totalFullCount) -nonewline
      $avg = $totalFullDataSize/($totalFullCount*1000*1000*1000)
      write-host ("  Avg Full Data (VM) Size on disk (GB):","{0:N2}" -f ($avg)) -nonewline
      $perfile = "" | Select "job","path","data_size","backup_size"
      $perfile.job = $($jb.Name)
      $perfile.path = "Full Avg Data (VM) Size (GB)"
      $perfile.data_size = ("{0:N2}" -f $avg)
      $OutArray += ,$perfile

      # Keep a running total of avg sizes across jobs
      $AvgFullDSTotal += $avg

      $avg = $totalFull/($totalFullCount*1000*1000*1000)
      write-host ("  Avg Full Backup Size on disk (GB):","{0:N2}" -f ($avg))
      $perfile = "" | Select "job","path","data_size","backup_size"
      $perfile.job = $($jb.Name)
      $perfile.path = "Full Avg Backup Size on disk (GB)"
      $perfile.backup_size = ("{0:N2}" -f $avg)
      $OutArray += ,$perfile

      # Keep a running total of avg sizes across jobs
      $AvgFullBSTotal += $avg
    } else {
      write-host ("    No Full Backups for this job in this repository.")
    }


    write-host ("    Total Data (VM) Size across all backups (GB):","{0:N2}" -f ($totalDS/(1000*1000*1000))) -nonewline
    write-host (", Total Backup Size across all backups on disk (GB):","{0:N2}" -f ($totalBS/(1000*1000*1000)))
    if ($totalBS -gt 0) {
      write-host ("  Combined dedup for job $($name):") -nonewline
      write-host (" {0:N2}" -f (($totalDS/$totalBS)*$egridDedup)) -nonewline -ForegroundColor green
      write-host (" (Veeam") -nonewline
      write-host (" {0:N2}" -f ($totalDS/$totalBS)) -nonewline -ForegroundColor green
      write-host (") over $totalCount total backups ")

      if ($verbose -ge 2) {
        $OutArray | export-csv -Append $csvFileName -NoTypeInformation
        $OutArray = $null
      }
    }
  } # foreach ($bu in $repo.getBackups()) 

  if ($totalRepoCount -gt 0) {
    write-host "Overall dedup ratio (X:1) for repository " $repo.Name " is : " -nonewline
    write-host ("Combined") -nonewline
    write-host (" {0:N2}" -f (($totalRepoDS/$totalRepoBS)*$egridDedup)) -nonewline -ForegroundColor green
    write-host (" (Veeam") -nonewline
    write-host (" {0:N2}" -f ($totalRepoDS/$totalRepoBS)) -nonewline -ForegroundColor green
    write-host (") over $totalRepoCount total backups")
    write-host ("Total Repository Data (VM) Size across all backups (GB):","{0:N2}" -f ($totalRepoDS/(1000*1000*1000))) -nonewline
    write-host (", Total Repository Backup Size on disk across all backups (GB):","{0:N2}" -f ($totalRepoBS/(1000*1000*1000)))
  }
  write-host ("")
} # foreach ($repo in (Get-VBRBackupRepository))

if ($totalTotalBS -gt 0) {
  write-host "Combined dedup ratio (X:1) for total of all Veeam backups when ExaGrid dedup is",$egridDedup," is shown below. Calculated using Veeam's TotalDataSize/TotalBackupSize: "
  write-host "- Veeam DataSize is datastore actually consumed by VMs across all backups"
  write-host "- Veeam Backup Size is the amount actually sent to the ExaGrid  across all backups - Veeam dedup and compression makes this less than DataSize"
  write-host "- No information is actually collected from the ExaGrids - actuall ExaGrid dedup ratio can be entered as a decimal value as a paramter to this script"
  write-host("Overall dedup ratio (X:1) for all jobs in all repositories is : ") -nonewline
  write-host ("Combined Dedup:") -nonewline
  write-host (" {0:N2}" -f (($totalTotalDS/$totalTotalBS)*$egridDedup)) -nonewline -ForegroundColor green
  write-host (" (Veeam") -nonewline
  write-host (" {0:N2}" -f ($totalTotalDS/$totalTotalBS)) -nonewline -ForegroundColor green
  write-host (", ExaGrid ") -nonewline
  write-host ("{0:N2}" -f $egridDedup) -nonewline -ForegroundColor green
  write-host (") over $totalTotalCount total retained backups in $totalRepos repositories")
  write-host ("Total Total Veeam DataSize across all backups (GB):","{0:N2}" -f ($totalTotalDS/(1000*1000*1000))) -nonewline
  write-host (", Total Total Veeam Backup Size across all backups on disk (GB):","{0:N2}" -f ($totalTotalBS/(1000*1000*1000)))
}
if ($AvgIncDSTotal -gt 0) { 
  write-host ("Total of all Incremental average Data (VM) Size (GB) is:","{0:N2}" -f $AvgIncDSTotal)
  $perfile = "" | Select "job","path","data_size","backup_size"
  $perfile.job = "Total Total"
  $perfile.path = "Incr Avg Data (VM) Size (GB)"
  $perfile.data_size = ("{0:N2}" -f $AvgIncDSTotal)
  $OutArray += ,$perfile
}
if ($AvgFullDSTotal -gt 0) { 
  write-host ("Total of all Full average Data (VM) Size (GB) is:","{0:N2}" -f $AvgFullDSTotal) 
  $perfile = "" | Select "job","path","data_size","backup_size"
  $perfile.job = "Total Total"
  $perfile.path = "Full Avg Data (VM) Size (GB)"
  $perfile.data_size = ("{0:N2}" -f $AvgFullDSTotal)
  $OutArray += ,$perfile
}
if ($AvgIncBSTotal -gt 0) { 
  write-host ("Total of all Incremental average Backup on disk Size (GB) is:","{0:N2}" -f $AvgIncDSTotal) 
  $perfile = "" | Select "job","path","data_size","backup_size"
  $perfile.job = "Total Total"
  $perfile.path = "Incr Avg Backup Size on disk (GB)"
  $perfile.backup_size = ("{0:N2}" -f $AvgIncBSTotal)
  $OutArray += ,$perfile
}
if ($AvgFullBSTotal -gt 0) { 
  write-host ("Total of all Full average Backup on disk size  is:","{0:N2}" -f $AvgFullDSTotal) 
  $perfile = "" | Select "job","path","data_size","backup_size"
  $perfile.job = "Total Total"
  $perfile.path = "Full Avg Backup Size on disk (GB)"
  $perfile.backup_size = ("{0:N2}" -f $AvgFullBSTotal)
  $OutArray += ,$perfile
}
 
if ($verbose -ge 2) {
  $OutArray | export-csv -Append $csvFileName -NoTypeInformation
  $OutArray = $null
}
