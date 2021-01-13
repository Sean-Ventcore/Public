@{
    tenantName = "yourTenant"
    tenantDomain = "yourTenant.com"
    appID = $null
    thumbprint = $null

    extensionTypes = 
    @{
        "Text"=@("doc","docx","txt")
        "Images"=@("cr2","jpg")
        "Spreadsheets"=@("xls","xlsx","ods")
        "PDF"=@("pdf")
        "Scripts"=@("ps1","psm1","bat","py")
        "Code"=@("cs","resx","settings","csproj","pdb","cache","sln","manifest","resources","suo")
        "Music"=@("mp3","ogg")
        "Video"=@("mp4","mov","avi","mpg","mpeg","mkv")
        "Data"=@("xml")
        "Archives"=@("zip","rar")
        "Passwords"=@("kdbx")
        "Executables"=@("exe")
        "Other"=@("thm")
    }
}