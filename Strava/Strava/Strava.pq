section Strava;

//
// OAuth configuration settings
//
// You MUST replace the values below for values for your own application.
// Signin to Strava and navigate to https://www.strava.com/settings/api 
// Follow the steps and obtain your client_id and client_secret.
// Set your Redirect URI value in your application registration to match the value below.
// Update the values within the "client_id" and "client_secret" files in the project.
// 
// Note: due to incompatibilities with the Internet Explorer control used in Visual Studio,
// you will not be able to authorize a new Strava application during the OAuth flow. You can workaround
// this by loading your extension in Power BI Desktop, and completing the OAuth flow there. 
// Once the application has been authorized for a given user, then the OAuth flow will work when 
// run in Visual Studio.

client_id = Text.FromBinary(Extension.Contents("client_id"));
client_secret = Text.FromBinary(Extension.Contents("client_secret"));
redirect_uri = "https://preview.powerbi.com/views/oauthredirect.html";
activity_uri = "https://www.strava.com/api/v3/athlete/activities?per_page=200";
windowWidth = 1200;
windowHeight = 1000;

//
// Exported functions
//
// These functions are exported to the M Engine (making them visible to end users), and associates 
// them with the specified Data Source Kind. The Data Source Kind is used when determining which 
// credentials to use during evaluation. Credential matching is done based on the function's parameters. 
// All data source functions associated to the same Data Source Kind must have a matching set of required 
// function parameters, including type, name, and the order in which they appear. 

[DataSource.Kind="Strava", Publish="Strava.UI"]
shared Strava.Contents = Value.ReplaceType(StravaData.Contents, type function (url as Uri.Type) as any);

[DataSource.Kind="Strava"]
shared Strava.PagedTable = Value.ReplaceType(StravaData.PagedTable, type function (url as Uri.Type) as any);


//
// Data Source definition
//
Strava = [
    Authentication = [
        OAuth = [
            StartLogin = StartLogin,
            FinishLogin = FinishLogin,
            Label = Extension.LoadString("AuthenticationLabel")
        ]
    ],
    Label = Extension.LoadString("DataSourceLabel")
];

//
// UI Export definition
//
Strava.UI = [
    Beta = true,
    ButtonText = { Extension.LoadString("FormulaTitle"), Extension.LoadString("FormulaHelp") },
    SourceImage = Strava.Icons,
    SourceTypeImage = Strava.Icons
];

Strava.Icons = [
    Icon16 = { Extension.Contents("Strava16.png"), Extension.Contents("Strava20.png"), Extension.Contents("Strava24.png"), Extension.Contents("Strava32.png") },
    Icon32 = { Extension.Contents("Strava32.png"), Extension.Contents("Strava40.png"), Extension.Contents("Strava48.png"), Extension.Contents("Strava64.png") }
];

StravaData.Contents = (url as text) =>
    let
        content = Web.Contents(url),
        link = GetNextLink(Value.Metadata(content)[Headers][#"Link"]?),
        json = Json.Document(content)
    in
        json meta [Next=link];

StravaData.PagedTable = (url as text) => Table.GenerateByPage((previous) =>
    let
        next = if previous = null then null else Value.Metadata(previous)[Next],
        current = if previous <> null and next = null then null else StravaData.Contents(if next = null then url else next),
        link = if current = null then null else Value.Metadata(current)[Next],
        table = if current = null then null else Table.FromList(current, Splitter.SplitByNothing(), null, null, ExtraValues.Error)
    in
        table meta [Next=link]);

StartLogin = (resourceUrl, state, display) =>
    let
        AuthorizeUrl = "https://www.strava.com/oauth/authorize?" & Uri.BuildQueryString([
            client_id = client_id,
            scope = "public",
            response_type = "code",
            state = state,
            redirect_uri = redirect_uri])
    in
        [
            LoginUri = AuthorizeUrl,
            CallbackUri = redirect_uri,
            WindowHeight = windowHeight,
            WindowWidth = windowWidth,
            Context = null
        ];

FinishLogin = (context, callbackUri, state) =>
    let
        Parts = Uri.Parts(callbackUri)[Query]
    in
        TokenMethod(Parts[code]);

TokenMethod = (code) =>
    let
        Response = Web.Contents("https://www.strava.com/oauth/token", [
            Content = Text.ToBinary(Uri.BuildQueryString([
                client_id = client_id,
                client_secret = client_secret,
                code = code,
                redirect_uri = redirect_uri])),
            Headers=[#"Content-type" = "application/x-www-form-urlencoded",#"Accept" = "application/json"]]),
        Parts = Json.Document(Response)
    in
        Parts;

Table.GenerateByPage = (getNextPage as function) as table =>
    let
        listOfPages = List.Generate(
            () => getNextPage(null),
            (lastPage) => lastPage <> null,
            (lastPage) => getNextPage(lastPage)
        ),
        tableOfPages = Table.FromList(listOfPages, Splitter.SplitByNothing(), {"Column1"}),
        firstRow = tableOfPages{0}?
    in
        if (firstRow = null) then
            Table.FromRows({})
        else
            Value.ReplaceType(
                Table.ExpandTableColumn(tableOfPages, "Column1", Table.ColumnNames(firstRow[Column1])),
                Value.Type(firstRow[Column1])
            );

GetNextLink = (link) =>
    let
        links = Text.Split(link, ","),
        splitLinks = List.Transform(links, each Text.Split(Text.Trim(_), ";")),
        next = List.Select(splitLinks, each Text.Trim(_{1}) = "rel=""next"""),
        first = List.First(next),
        removedBrackets = Text.Range(first{0}, 1, Text.Length(first{0}) - 2)
    in
        try removedBrackets otherwise null;