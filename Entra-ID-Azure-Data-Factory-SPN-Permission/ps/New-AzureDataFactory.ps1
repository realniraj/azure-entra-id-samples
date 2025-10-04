<#
.SYNOPSIS
    Creates a new Azure Data Factory (V2) instance in a specified resource group.

.DESCRIPTION
    This script automates the creation of an Azure Data Factory. It will first check
    if the specified resource group exists in the given location, and if not, it will
    create it. Then, it proceeds to create the Data Factory.

    This script uses the Az PowerShell module and requires an authenticated Azure session.
    When you run it, it will prompt you to log in to your Azure account if you are not
    already connected.

.PARAMETER DataFactoryName
    The name for the new Azure Data Factory. This name must be globally unique.

.PARAMETER ResourceGroupName
    The name of the resource group where the Data Factory will be created.

.PARAMETER Location
    The Azure region where the resource group and Data Factory will be located (e.g., 'EastUS', 'WestEurope').

.EXAMPLE
    .\New-AzureDataFactory.ps1 -DataFactoryName "my-unique-adf-instance" -ResourceGroupName "my-adf-rg" -Location "EastUS"

    This command creates a new Azure Data Factory named 'my-unique-adf-instance' in the 'my-adf-rg'
    resource group located in the 'EastUS' region. If the resource group doesn't exist, it will be created.

.EXAMPLE
    .\New-AzureDataFactory.ps1 -DataFactoryName "my-prod-adf" -ResourceGroupName "production-resources" -Location "WestEurope" -Verbose

    This command runs the script with detailed verbose output, showing each step of the process.
#>
[CmdletBinding(SupportsShouldProcess = $true)]
param(
    [Parameter(Mandatory = $true, HelpMessage = "The globally unique name of the new Azure Data Factory.")]
    [string]$DataFactoryName,

    [Parameter(Mandatory = $true, HelpMessage = "The name of the resource group for the Data Factory.")]
    [string]$ResourceGroupName,

    [Parameter(Mandatory = $true, HelpMessage = "The Azure region for the resources (e.g., 'EastUS').")]
    [string]$Location
)

begin {
    # --- Step 1: Check for Az Module and Connect to Azure ---
    Write-Verbose "Checking for Az module and Azure connection..."
    try {
        if (-not (Get-Module -ListAvailable -Name Az.Accounts)) {
            throw "The 'Az.Accounts' PowerShell module is not installed. Please run 'Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force'."
        }

        if (-not (Get-AzContext)) {
            Write-Host "Not connected to Azure. Connecting now..." -ForegroundColor Yellow
            Connect-AzAccount
        }
        Write-Verbose "Successfully connected to Azure account: $((Get-AzContext).Account)"
    }
    catch {
        Write-Error "Failed to connect to Azure. Error: $_"
        return # Stop script execution
    }
}

process {
    # --- Step 2: Create Resource Group if it doesn't exist ---
    try {
        Write-Verbose "Checking for resource group '$ResourceGroupName' in location '$Location'..."
        $rg = Get-AzResourceGroup -Name $ResourceGroupName -ErrorAction SilentlyContinue
        if (-not $rg) {
            if ($PSCmdlet.ShouldProcess($ResourceGroupName, "Create Resource Group")) {
                Write-Host "Resource group '$ResourceGroupName' not found. Creating it now in '$Location'..." -ForegroundColor Yellow
                New-AzResourceGroup -Name $ResourceGroupName -Location $Location -Force | Out-Null
                Write-Host "Successfully created resource group '$ResourceGroupName'." -ForegroundColor Green
            }
        }
        else {
            Write-Host "Resource group '$ResourceGroupName' already exists." -ForegroundColor Green
        }
    }
    catch {
        Write-Error "Failed to get or create resource group '$ResourceGroupName'. Error: $_"
        return
    }

    # --- Step 3: Create the Azure Data Factory ---
    try {
        if ($PSCmdlet.ShouldProcess($DataFactoryName, "Create Azure Data Factory in resource group '$ResourceGroupName'")) {
            Write-Host "Creating Azure Data Factory '$DataFactoryName'..." -ForegroundColor Cyan
            $adf = New-AzDataFactoryV2 -ResourceGroupName $ResourceGroupName -Name $DataFactoryName -Location $Location
            Write-Host "Successfully created Azure Data Factory '$DataFactoryName'." -ForegroundColor Green
            Write-Host "ADF Portal URL: $($adf.DataFactoryUrl)"
        }
    }
    catch {
        Write-Error "Failed to create Azure Data Factory '$DataFactoryName'. Error: $_"
    }
}

end {
    Write-Verbose "Script finished."
}