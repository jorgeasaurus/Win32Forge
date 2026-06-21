@{
    Severity     = @('Error', 'Warning')

    ExcludeRules = @(
        # The source is intentionally UTF-8 without BOM.
        'PSUseBOMForUnicodeEncodedFile'
    )
}
