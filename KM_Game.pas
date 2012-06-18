unit KM_Game;
{$I KaM_Remake.inc}
interface
uses
  {$IFDEF MSWindows} Windows, {$ENDIF}
  {$IFDEF Unix} LCLIntf, LCLType, FileUtil, {$ENDIF}
  Forms, Controls, Classes, Dialogs, ExtCtrls, SysUtils, KromUtils, Math, TypInfo,
  {$IFDEF USE_MAD_EXCEPT} MadExcept, KM_Exceptions, {$ENDIF}
  KM_CommonTypes, KM_Defaults, KM_Points,
  KM_GameInputProcess, KM_GameOptions,
  KM_InterfaceDefaults, KM_InterfaceMapEditor, KM_InterfaceGamePlay,
  KM_Networking, KM_PathFinding, KM_PerfLog, KM_Projectiles, KM_Render,
  KM_Viewport;

type
  TGameMode = (
    gmSingle,
    gmMulti, //Different GIP, networking,
    gmMapEd, //Army handling, lite updates,
    gmReplay //No input
    );

  //Methods relevant to gameplay
  TKMGame = class
  private //Irrelevant to savegame
    fTimerGame: TTimer;
    fGameOptions: TKMGameOptions;
    fNetworking: TKMNetworking;
    fProjectiles: TKMProjectiles;
    fGameInputProcess: TGameInputProcess;
    fPathfinding: TPathFinding;
    fViewport: TViewport;
    fPerfLog: TKMPerfLog;
    fActiveInterface: TKMUserInterface; //Shortcut for both of UI
    fGamePlayInterface: TKMGamePlayInterface;
    fMapEditorInterface: TKMapEdInterface;

    fIsExiting: Boolean; //Set this to true on Exit and unit/house pointers will be released without cross-checking
    fIsEnded: Boolean; //The game has ended/crashed and further UpdateStates are not required/impossible
    fIsPaused: Boolean;
    fGameSpeed: Word; //Actual speedup value
    fGameSpeedMultiplier: Word; //How many ticks are compressed into one
    fGameMode: TGameMode;
    fMissionFile: string; //Path to mission we are playing, so it gets saved to crashreport
    fReplayFile: string;
    fWaitingForNetwork: Boolean;
    fAdvanceFrame: Boolean; //Replay variable to advance 1 frame, afterwards set to false

  //Should be saved
    fGameTickCount: Cardinal;
    fGameName: string;
    fCampaignName: AnsiString; //Is this a game part of some campaign
    fCampaignMap: Byte; //Which campaign map it is, so we can unlock next one on victory
    fMissionMode: TKMissionMode;
    fIDTracker: Cardinal; //Units-Houses tracker, to issue unique IDs

    procedure GameMPDisconnect(const aData:string);
    procedure MultiplayerRig;
    procedure UpdateUI;
  public
    PlayOnState: TGameResultMsg;
    DoGameHold: Boolean; //Request to run GameHold after UpdateState has finished
    DoGameHoldState: TGameResultMsg; //The type of GameHold we want to occur due to DoGameHold
    SkipReplayEndCheck: Boolean;
    constructor Create(aGameMode: TGameMode; aRender: TRender; aNetworking: TKMNetworking);
    destructor Destroy; override;

    procedure KeyDown(Key: Word; Shift: TShiftState);
    procedure KeyPress(Key: Char);
    procedure KeyUp(Key: Word; Shift: TShiftState);
    procedure MouseDown(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
    procedure MouseMove(Shift: TShiftState; X,Y: Integer);
    procedure MouseUp(Button: TMouseButton; Shift: TShiftState; X,Y: Integer);
    procedure MouseWheel(Shift: TShiftState; WheelDelta: Integer; X,Y: Integer);

    procedure GameStart(aMissionFile, aGameName, aCampName: string; aCampMap: Byte); overload;
    procedure GameStart(aSizeX, aSizeY: Integer); overload;
    procedure Load(const aFileName: string; aReplay:boolean=false);

    function MapX: Word;
    function MapY: Word;

    procedure Resize(X,Y: Integer);

    procedure GameMPPlay(Sender:TObject);
    procedure GameMPReadyToPlay(Sender:TObject);
    procedure GameHold(DoHold:boolean; Msg:TGameResultMsg); //Hold the game to ask if player wants to play after Victory/Defeat/ReplayEnd
    procedure RequestGameHold(Msg:TGameResultMsg);
    procedure PlayerVictory(aPlayerIndex:TPlayerIndex);
    procedure PlayerDefeat(aPlayerIndex:TPlayerIndex);
    procedure GameWaitingForNetwork(aWaiting:boolean);
    procedure GameDropWaitingPlayers;

    procedure AutoSave;
    procedure BaseSave;
    procedure SaveMapEditor(const aMissionName:string; aMultiplayer:boolean);

    procedure RestartReplay;

    function MissionTime:TDateTime;
    function GetPeacetimeRemaining:TDateTime;
    function CheckTime(aTimeTicks:cardinal):boolean;
    function IsPeaceTime:boolean;
    function IsMultiplayer: Boolean;
    function IsReplay: Boolean;
    procedure ShowMessage(aKind: TKMMessageKind; aText: string; aLoc: TKMPoint);
    procedure UpdatePeaceTime;
    property GameTickCount:cardinal read fGameTickCount;
    property GameName: string read fGameName;
    property CampaignName: AnsiString read fCampaignName;
    property CampaignMap: Byte read fCampaignMap;

    property GameMode: TGameMode read fGameMode;

    property IsExiting:boolean read fIsExiting;
    property IsPaused:boolean read fIsPaused write fIsPaused;
    property MissionMode:TKMissionMode read fMissionMode write fMissionMode;
    function GetNewID:cardinal;
    procedure SetGameSpeed(aSpeed: word);
    procedure StepOneFrame;
    function SaveName(const aName, aExt: string; aMultiPlayer: Boolean): string;

    procedure UpdateGameCursor(X,Y: Integer; Shift: TShiftState);

    property Networking: TKMNetworking read fNetworking;
    property Pathfinding: TPathFinding read fPathfinding;
    property Projectiles: TKMProjectiles read fProjectiles;
    property GameInputProcess: TGameInputProcess read fGameInputProcess;
    property GameOptions: TKMGameOptions read fGameOptions;
    property GamePlayInterface: TKMGamePlayInterface read fGamePlayInterface;
    property MapEditorInterface: TKMapEdInterface read fMapEditorInterface;
    property Viewport: TViewport read fViewport;

    procedure Save(const aFileName: string);
    {$IFDEF USE_MAD_EXCEPT}
    procedure AttachCrashReport(const ExceptIntf: IMEException; aZipFile:string);
    {$ENDIF}
    procedure ReplayInconsistancy;

    procedure Render(aRender: TRender);
    procedure UpdateGame(Sender: TObject);
    procedure UpdateState(aGlobalTickCount: Cardinal);
    procedure UpdateStateIdle(aFrameTime: Cardinal);
  end;


var
  fGameG: TKMGame;


implementation
uses
  KM_CommonClasses, KM_Log, KM_Utils,
  KM_ArmyEvaluation, KM_EventProcess, KM_GameApp, KM_GameInfo, KM_MissionScript,
  KM_Player, KM_PlayersCollection, KM_RenderPool, KM_Resource, KM_ResourceCursors,
  KM_Settings, KM_Sound, KM_Terrain, KM_TextLibrary,
  KM_GameInputProcess_Single, KM_GameInputProcess_Multi;


{ Creating everything needed for MainMenu, game stuff is created on StartGame }
//aMultiplayer - is this a multiplayer game
//aRender - who will be rendering the Game session
constructor TKMGame.Create(aGameMode: TGameMode; aRender: TRender; aNetworking: TKMNetworking);
begin
  inherited Create;

  fGameMode := aGameMode;
  fNetworking := aNetworking;

  fAdvanceFrame := False;
  fIDTracker    := 0;
  PlayOnState   := gr_Cancel;
  DoGameHold    := False;
  SkipReplayEndCheck := False;
  fWaitingForNetwork := False;
  fGameOptions  := TKMGameOptions.Create;

  if fGameMode = gmMapEd then
  begin
    fMapEditorInterface := TKMapEdInterface.Create(aRender.ScreenX, aRender.ScreenY);
    fActiveInterface := fMapEditorInterface;
  end
  else
  begin
    //Create required UI (gameplay or MapEd)
    fGamePlayInterface := TKMGamePlayInterface.Create(aRender.ScreenX, aRender.ScreenY, IsMultiplayer);
    fActiveInterface := fGamePlayInterface;
  end;

  //todo: Maybe we should reset the GameCursor? If I play 192x192 map, quit, and play a 64x64 map
  //      my cursor could be at (190,190) if the player starts with his cursor over the controls panel...
  //      This caused a crash in RenderCursors which I fixed by adding range checking to CheckTileRevelation
  //      (good idea anyway) There could be other crashes caused by this.
  fViewport := TViewport.Create(aRender.ScreenX, aRender.ScreenY);

  fTimerGame := TTimer.Create(nil);
  SetGameSpeed(1); //Initialize relevant variables
  fTimerGame.OnTimer := UpdateGame;
  fTimerGame.Enabled := True;

  //Here comes terrain/mission init
  SetKaMSeed(4); //Every time the game will be the same as previous. Good for debug.
  fTerrain := TTerrain.Create;

  InitUnitStatEvals; //Army

  fPerfLog := TKMPerfLog.Create;
  fLog.AppendLog('<== Game creation is done ==>');
  fPathfinding := TPathfinding.Create;
  fProjectiles := TKMProjectiles.Create;
  fEventsManager := TKMEventsManager.Create;

  fRenderPool := TRenderPool.Create(aRender);

  fGameTickCount := 0; //Restart counter
end;


{ Destroy what was created }
destructor TKMGame.Destroy;
begin
  fTimerGame.Enabled := False;

  if (fGameInputProcess <> nil) and (fGameInputProcess.ReplayState = gipRecording) then
    fGameInputProcess.SaveToFile(SaveName('basesave', 'rpl', fGameMode = gmMulti));

  fPerfLog.SaveToFile(ExeDir + 'Logs\PerfLog.txt');

  FreeAndNil(fTimerGame);

  FreeThenNil(fGamePlayInterface);
  FreeThenNil(fMapEditorInterface);

  FreeAndNil(fGameInputProcess);
  FreeAndNil(fRenderPool);
  FreeAndNil(fGameOptions);
  fPerfLog.Free;
  inherited;
end;


procedure TKMGame.Resize(X,Y: Integer);
begin
  fActiveInterface.Resize(X, Y);

  fViewport.Resize(X, Y);
end;


function TKMGame.MapX: Word;
begin
  Result := fTerrain.MapX;
end;


function TKMGame.MapY: Word;
begin
  Result := fTerrain.MapY;
end;


procedure TKMGame.KeyDown(Key: Word; Shift: TShiftState);
begin
  fActiveInterface.KeyDown(Key, Shift);
end;


procedure TKMGame.KeyPress(Key: Char);
begin
  fActiveInterface.KeyPress(Key);
end;


procedure TKMGame.KeyUp(Key: Word; Shift: TShiftState);
begin
  fActiveInterface.KeyUp(Key, Shift);
end;


procedure TKMGame.MouseDown(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  fActiveInterface.MouseDown(Button,Shift,X,Y);
end;


procedure TKMGame.MouseMove(Shift: TShiftState; X,Y: Integer);
begin
  fActiveInterface.MouseMove(Shift, X,Y);end;


procedure TKMGame.MouseUp(Button: TMouseButton; Shift: TShiftState; X, Y: Integer);
begin
  fActiveInterface.MouseUp(Button, Shift, X,Y);
end;


procedure TKMGame.MouseWheel(Shift: TShiftState; WheelDelta: Integer; X, Y: Integer);
var PrevCursor: TKMPointF;
begin
  fActiveInterface.MouseWheel(Shift, WheelDelta, X, Y);

  if (X < 0) or (Y < 0) then Exit; //This occours when you use the mouse wheel on the window frame

  //Allow to zoom only when curor is over map. Controls handle zoom on their own
  if MOUSEWHEEL_ZOOM_ENABLE and (fActiveInterface.MyControls.CtrlOver = nil) then
  begin
    UpdateGameCursor(X, Y, Shift); //Make sure we have the correct cursor position to begin with
    PrevCursor := GameCursor.Float;
    fViewport.Zoom := fViewport.Zoom + WheelDelta / 2000;
    UpdateGameCursor(X, Y, Shift); //Zooming changes the cursor position
    //Move the center of the screen so the cursor stays on the same tile, thus pivoting the zoom around the cursor
    fViewport.Position := KMPointF(fViewport.Position.X + PrevCursor.X-GameCursor.Float.X,
                                   fViewport.Position.Y + PrevCursor.Y-GameCursor.Float.Y);
    UpdateGameCursor(X, Y, Shift); //Recentering the map changes the cursor position
  end;
end;


procedure TKMGame.GameStart(aMissionFile, aGameName, aCampName: string; aCampMap: Byte);
var
  I: Integer;
  ParseMode: TMissionParsingMode;
  PlayerRemap: TPlayerArray;
  Parser: TMissionParserStandard;
begin
  fLog.AppendLog('GameStart');

  fGameName := aGameName;
  fCampaignName := aCampName;
  fCampaignMap := aCampMap;
  fMissionFile := aMissionFile;

  fLog.AppendLog('Loading DAT file: ' + aMissionFile);

  if fGameMode = gmMulti then
  begin
    for i:=0 to High(PlayerRemap) do
      PlayerRemap[i] := PLAYER_NONE; //Init with empty values
    for i:=1 to fNetworking.NetPlayers.Count do
    begin
      PlayerRemap[fNetworking.NetPlayers[i].StartLocation - 1] := i-1; //PlayerID is 0 based
      fNetworking.NetPlayers[i].StartLocation := i;
    end;
  end
  else
    for i:=0 to High(PlayerRemap) do
      PlayerRemap[i] := i; //Init with empty values

  case fGameMode of
    gmMulti:  ParseMode := mpm_Multi;
    gmMapEd:  ParseMode := mpm_Editor;
    gmSingle: ParseMode := mpm_Single;
    else      Assert(False);
  end;

  Parser := TMissionParserStandard.Create(ParseMode, PlayerRemap, False);
  try
    if not Parser.LoadMission(aMissionFile) then
      raise Exception.Create(Parser.ErrorMessage);

    MyPlayer := fPlayers.Player[Parser.MissionInfo.HumanPlayerID];
    Assert(MyPlayer.PlayerType = pt_Human);
    fMissionMode := Parser.MissionInfo.MissionMode;
  finally
    Parser.Free;
  end;

  fEventsManager.LoadFromFile(ChangeFileExt(aMissionFile, '.evt'));
  fTextLibrary.LoadMissionStrings(ChangeFileExt(aMissionFile, '.%s.libx'));

  fPlayers.AfterMissionInit(true);

  if fGameMode = gmMapEd then
  begin
    MyPlayer := fPlayers.Player[0];
    fPlayers.AddPlayers(MAX_PLAYERS - fPlayers.Count); //Activate all players
  end;

  fLog.AppendLog('Gameplay initialized', true);

  if fGameMode = gmMulti then
    fGameInputProcess := TGameInputProcess_Multi.Create(gipRecording, fNetworking)
  else
    fGameInputProcess := TGameInputProcess_Single.Create(gipRecording);

  if fGameMode = gmMulti then
    MultiplayerRig;

  //When everything is ready we can update UI
  UpdateUI;

  BaseSave;
  fLog.AppendLog('Gameplay recording initialized',true);
  SetKaMSeed(4); //Random after StartGame and ViewReplay should match
end;


//All setup data gets taken from fNetworking class
procedure TKMGame.MultiplayerRig;
var
  i,k:integer;
  PlayerIndex:TPlayerIndex;
  PlayerUsed:array[0..MAX_PLAYERS-1]of boolean;
begin
  //Copy all game options from lobby to this game
  fGameOptions.Peacetime := fNetworking.NetGameOptions.Peacetime;

  FillChar(PlayerUsed, SizeOf(PlayerUsed), #0);
  //Assign existing NetPlayers(1..N) to map players(0..N-1)
  for i:=1 to fNetworking.NetPlayers.Count do
  begin
    PlayerIndex := fNetworking.NetPlayers[i].StartLocation - 1; //PlayerID is 0 based
    fNetworking.NetPlayers[i].PlayerIndex := fPlayers.Player[PlayerIndex];
    fPlayers.Player[PlayerIndex].PlayerType := fNetworking.NetPlayers[i].GetPlayerType;
    fPlayers.Player[PlayerIndex].PlayerName := fNetworking.NetPlayers[i].Nikname;

    //Setup alliances
    if fNetworking.SelectGameKind = ngk_Map then
      for k:=0 to fPlayers.Count-1 do
        if (fNetworking.NetPlayers[i].Team = 0) or (fNetworking.NetPlayers.StartingLocToLocal(k+1) = -1) or
          (fNetworking.NetPlayers[i].Team <> fNetworking.NetPlayers[fNetworking.NetPlayers.StartingLocToLocal(k+1)].Team) then
          fPlayers.Player[PlayerIndex].Alliances[k] := at_Enemy
        else
          fPlayers.Player[PlayerIndex].Alliances[k] := at_Ally;

    fPlayers.Player[PlayerIndex].FlagColor := fNetworking.NetPlayers[i].FlagColor;
    PlayerUsed[PlayerIndex] := true;
  end;

  //MyPlayer is a pointer to TKMPlayer
  MyPlayer := fPlayers.Player[fNetworking.NetPlayers[fNetworking.MyIndex].StartLocation-1];

  //Clear remaining players
  for i:=fPlayers.Count-1 downto 0 do
    if not PlayerUsed[i] then
      if fNetworking.SelectGameKind = ngk_Map then
        fPlayers.RemovePlayer(i)
      else
        //We cannot remove a player from a save (as they might be interacting with other players) so make them inactive (uncontrolled human)
        fPlayers[i].PlayerType := pt_Human;

  fPlayers.SyncFogOfWar; //Syncs fog of war revelation between players AFTER alliances
  if fNetworking.SelectGameKind = ngk_Map then
    fPlayers.AddDefaultMPGoals(fMissionMode); //Multiplayer missions don't have goals yet, so add the defaults

  fViewport.ResizeMap(fTerrain.MapX, fTerrain.MapY);
  fViewport.Position := KMPointF(MyPlayer.CenterScreen);
  fViewport.ResetZoom; //This ensures the viewport is centered on the map

  fLog.AppendLog('Gameplay initialized', true);

  fNetworking.OnPlay           := GameMPPlay;
  fNetworking.OnReadyToPlay    := GameMPReadyToPlay;
  fNetworking.OnCommands       := TGameInputProcess_Multi(fGameInputProcess).RecieveCommands;
  fNetworking.OnTextMessage    := fGamePlayInterface.ChatMessage;
  fNetworking.OnPlayersSetup   := fGamePlayInterface.AlliesOnPlayerSetup;
  fNetworking.OnPingInfo       := fGamePlayInterface.AlliesOnPingInfo;
  fNetworking.OnDisconnect     := GameMPDisconnect; //For auto reconnecting
  fNetworking.OnReassignedHost := nil; //So it is no longer assigned to a lobby event
  fNetworking.GameCreated;

  if fNetworking.Connected and (fNetworking.NetGameState = lgs_Loading) then GameWaitingForNetwork(true); //Waiting for players
//  fGamePlayInterface.SetChatText(fMainMenuInterface.GetChatText); //Copy the typed lobby message to the in-game chat
//  fGamePlayInterface.SetChatMessages(fMainMenuInterface.GetChatMessages); //Copy the old chat messages to the in-game chat

  fLog.AppendLog('Gameplay recording initialized', True);
end;


//Everyone is ready to start playing
//Issued by fNetworking at the time depending on each Players lag individually
procedure TKMGame.GameMPPlay(Sender:TObject);
begin
  GameWaitingForNetwork(false); //Finished waiting for players
  fNetworking.AnnounceGameInfo(MissionTime, GameName);
  fLog.AppendLog('Net game began');
end;


procedure TKMGame.GameMPReadyToPlay(Sender:TObject);
begin
  //Update the list of players that are ready to play
  GameWaitingForNetwork(true);
end;


procedure TKMGame.GameMPDisconnect(const aData:string);
begin
  if fNetworking.NetGameState in [lgs_Game, lgs_Reconnecting] then
  begin
    if WRITE_RECONNECT_LOG then fLog.AppendLog('GameMPDisconnect: '+aData);
    fNetworking.PostLocalMessage('Connection failed: '+aData,false); //Debugging that should be removed later
    fNetworking.OnJoinFail := GameMPDisconnect; //If the connection fails (e.g. timeout) then try again
    fNetworking.OnJoinAssignedHost := nil;
    fNetworking.OnJoinSucc := nil;
    fNetworking.AttemptReconnection;
  end
  else
  begin
    fNetworking.Disconnect;
    fGameApp.Stop(gr_Disconnect, fTextLibrary[TX_GAME_ERROR_NETWORK]+' '+aData)
  end;
end;

{$IFDEF USE_MAD_EXCEPT}
procedure TKMGame.AttachCrashReport(const ExceptIntf: IMEException; aZipFile:string);

  procedure AttachFile(const aFile:string);
  begin
    if (aFile = '') or not FileExists(aFile) then Exit;
    ExceptIntf.AdditionalAttachments.Add(aFile, '', aZipFile);
  end;

var I: Integer;
begin
  fLog.AppendLog('Creating crash report...');

  if (fGameInputProcess <> nil) and (fGameInputProcess.ReplayState = gipRecording) then
    fGameInputProcess.SaveToFile(SaveName('basesave', 'rpl', fMultiplayerMode)); //Save replay data ourselves

  AttachFile(SaveName('basesave', 'rpl'));
  AttachFile(SaveName('basesave', 'bas'));
  AttachFile(SaveName('basesave', 'sav'));

  AttachFile(fMissionFile);

  for I := 1 to AUTOSAVE_COUNT do //All autosaves
  begin
    AttachFile(SaveName('autosave' + Int2Fix(I, 2), 'rpl'));
    AttachFile(SaveName('autosave' + Int2Fix(I, 2), 'bas'));
    AttachFile(SaveName('autosave' + Int2Fix(I, 2), 'sav'));
  end;

  fLog.AppendLog('Crash report created');
end;
{$ENDIF}


//Occasional replay inconsistencies are a known bug, we don't need reports of it
procedure TKMGame.ReplayInconsistancy;
begin
  //Stop game from executing while the user views the message
  fIsPaused := True;
  fLog.AppendLog('Replay failed a consistency check at tick '+IntToStr(fGameTickCount));
  if MessageDlg(fTextLibrary[TX_REPLAY_FAILED], mtWarning, [mbYes, mbNo], 0) <> mrYes then
    fGameApp.Stop(gr_Error, '')
  else
    fIsPaused := False;
end;


//Put the game on Hold for Victory screen
procedure TKMGame.GameHold(DoHold: Boolean; Msg: TGameResultMsg);
begin
  DoGameHold := false;
  fGamePlayInterface.ReleaseDirectionSelector; //In case of victory/defeat while moving troops
  fResource.Cursors.Cursor := kmc_Default;
  fViewport.ReleaseScrollKeys;
  PlayOnState := Msg;

  if DoHold then begin
    fIsPaused := True;
    fGamePlayInterface.ShowPlayMore(true, Msg);
  end else
    fIsPaused := False;
end;


procedure TKMGame.RequestGameHold(Msg:TGameResultMsg);
begin
  DoGameHold := true;
  DoGameHoldState := Msg;
end;


procedure TKMGame.PlayerVictory(aPlayerIndex: TPlayerIndex);
begin
  if aPlayerIndex = MyPlayer.PlayerIndex then
    fSoundLib.Play(sfxn_Victory, 1.0, true); //Fade music

  if fGameMode = gmMulti then
  begin
    if aPlayerIndex = MyPlayer.PlayerIndex then
    begin
      PlayOnState := gr_Win;
      fGamePlayInterface.ShowMPPlayMore(gr_Win);
    end;
  end
  else
    RequestGameHold(gr_Win);
end;


procedure TKMGame.PlayerDefeat(aPlayerIndex:TPlayerIndex);
begin
  if aPlayerIndex = MyPlayer.PlayerIndex then fSoundLib.Play(sfxn_Defeat, 1.0, true); //Fade music
  if fGameMode = gmMulti then
  begin
    fNetworking.PostLocalMessage(Format(fTextLibrary[TX_MULTIPLAYER_PLAYER_DEFEATED],
                                        [fPlayers[aPlayerIndex].PlayerName]));
    if aPlayerIndex = MyPlayer.PlayerIndex then
    begin
      PlayOnState := gr_Defeat;
      fGamePlayInterface.ShowMPPlayMore(gr_Defeat);
    end;
  end
  else
    RequestGameHold(gr_Defeat);
end;


//Display the overlay "Waiting for players"
//todo: Move to fNetworking and query GIP from there
procedure TKMGame.GameWaitingForNetwork(aWaiting: Boolean);
var WaitingPlayers: TStringList;
begin
  fWaitingForNetwork := aWaiting;

  WaitingPlayers := TStringList.Create;
  case fNetworking.NetGameState of
    lgs_Game, lgs_Reconnecting:
        //GIP is waiting for next tick
        TGameInputProcess_Multi(fGameInputProcess).GetWaitingPlayers(fGameTickCount+1, WaitingPlayers);
    lgs_Loading:
        //We are waiting during inital loading
        fNetworking.NetPlayers.GetNotReadyToPlayPlayers(WaitingPlayers);
    else
        Assert(false, 'GameWaitingForNetwork from wrong state '+GetEnumName(TypeInfo(TNetGameState), Integer(fNetworking.NetGameState)));
  end;

  fGamePlayInterface.ShowNetworkLag(aWaiting, WaitingPlayers, fNetworking.IsHost);
  WaitingPlayers.Free;
end;


//todo: Move to fNetworking and query GIP from there
procedure TKMGame.GameDropWaitingPlayers;
var WaitingPlayers: TStringList;
begin
  WaitingPlayers := TStringList.Create;
  case fNetworking.NetGameState of
    lgs_Game,lgs_Reconnecting:
        TGameInputProcess_Multi(fGameInputProcess).GetWaitingPlayers(fGameTickCount+1, WaitingPlayers); //GIP is waiting for next tick
    lgs_Loading:
        fNetworking.NetPlayers.GetNotReadyToPlayPlayers(WaitingPlayers); //We are waiting during inital loading
    else
        Assert(False); //Should not be waiting for players from any other GameState
  end;
  fNetworking.DropWaitingPlayers(WaitingPlayers);
  WaitingPlayers.Free;
end;


procedure TKMGame.GameStart(aSizeX, aSizeY: Integer);
var
  I: Integer;
begin
  fGameName := fTextLibrary[TX_MAP_ED_NEW_MISSION];

  fTerrain.MakeNewMap(aSizeX, aSizeY, True);
  fPlayers := TKMPlayersCollection.Create;
  fPlayers.AddPlayers(MAX_PLAYERS); //Create MAX players
  MyPlayer := fPlayers.Player[0];
  MyPlayer.PlayerType := pt_Human; //Make Player1 human by default

  //if FileExists(aFileName) then fMapEditorInterface.SetLoadMode(aMultiplayer);
  fPlayers.AfterMissionInit(false);

  for I := 0 to fPlayers.Count - 1 do //Reveal all players since we'll swap between them in MapEd
    fPlayers[I].FogOfWar.RevealEverything;

  //When everything is ready we can update UI
  UpdateUI;

  fLog.AppendLog('Gameplay initialized', True);
end;


procedure TKMGame.AutoSave;
var i: integer;
begin
  Save('autosave'); //Save to temp file

  //Delete last autosave and shift remaining by 1 position back
  DeleteFile(SaveName('autosave'+int2fix(AUTOSAVE_COUNT,2), 'sav', fGameMode = gmMulti));
  DeleteFile(SaveName('autosave'+int2fix(AUTOSAVE_COUNT,2), 'rpl', fGameMode = gmMulti));
  DeleteFile(SaveName('autosave'+int2fix(AUTOSAVE_COUNT,2), 'bas', fGameMode = gmMulti));
  for i:=AUTOSAVE_COUNT downto 2 do //03 to 01
  begin
    RenameFile(SaveName('autosave'+int2fix(i-1,2), 'sav', fGameMode = gmMulti), SaveName('autosave'+int2fix(i,2), 'sav', fGameMode = gmMulti));
    RenameFile(SaveName('autosave'+int2fix(i-1,2), 'rpl', fGameMode = gmMulti), SaveName('autosave'+int2fix(i,2), 'rpl', fGameMode = gmMulti));
    RenameFile(SaveName('autosave'+int2fix(i-1,2), 'bas', fGameMode = gmMulti), SaveName('autosave'+int2fix(i,2), 'bas', fGameMode = gmMulti));
  end;

  //Rename temp to be first in list
  RenameFile(SaveName('autosave', 'sav', fGameMode = gmMulti), SaveName('autosave01', 'sav', fGameMode = gmMulti));
  RenameFile(SaveName('autosave', 'rpl', fGameMode = gmMulti), SaveName('autosave01', 'rpl', fGameMode = gmMulti));
  RenameFile(SaveName('autosave', 'bas', fGameMode = gmMulti), SaveName('autosave01', 'bas', fGameMode = gmMulti));
end;


procedure TKMGame.BaseSave;
begin
  Save('basesave'); //Temp file

  //In Linux CopyFile does not overwrite
  if FileExists(SaveName('basesave', 'bas', fGameMode = gmMulti)) then
    DeleteFile(SaveName('basesave','bas', fGameMode = gmMulti));
  CopyFile(PChar(SaveName('basesave','sav', fGameMode = gmMulti)), PChar(SaveName('basesave','bas', fGameMode = gmMulti)), False);
end;


procedure TKMGame.SaveMapEditor(const aMissionName:string; aMultiplayer:boolean);
var
  i: integer;
  fMissionParser: TMissionParserStandard;
begin
  if aMissionName = '' then exit;

  //Prepare and save
  fPlayers.RemoveEmptyPlayers;
  ForceDirectories(ExeDir + 'Maps\' + aMissionName);
  fTerrain.SaveToFile(MapNameToPath(aMissionName, 'map', aMultiplayer));
  fMissionParser := TMissionParserStandard.Create(mpm_Editor, false);
  fMissionParser.SaveDATFile(MapNameToPath(aMissionName, 'dat', aMultiplayer));
  FreeAndNil(fMissionParser);

  fGameName := aMissionName;
  fPlayers.AddPlayers(MAX_PLAYERS - fPlayers.Count); // Activate all players

  //Reveal all players since we'll swap between them in MapEd
  for i := 0 to fPlayers.Count - 1 do
    fPlayers[i].FogOfWar.RevealEverything;

  if MyPlayer = nil then
    MyPlayer := fPlayers[0];
end;


procedure TKMGame.Render(aRender: TRender);
begin
  fRenderPool.Render;

  aRender.SetRenderMode(rm2D);
  fActiveInterface.Paint;
end;


//Restart the replay but do not change the viewport position/zoom
procedure TKMGame.RestartReplay;
var OldCenter: TKMPointF; OldZoom: Single;
begin
  OldCenter := fViewport.Position;
  OldZoom := fViewport.Zoom;

  fGameApp.NewReplay(fReplayFile);

  fViewport.Position := OldCenter;
  fViewport.Zoom := OldZoom;
end;


//TDateTime stores days/months/years as 1 and hours/minutes/seconds as fractions of a 1
//Treat 10 ticks as 1 sec irregardless of user-set pace
function TKMGame.MissionTime: TDateTime;
begin
  //Convert cardinal into TDateTime, where 1hour = 1/24 and so on..
  Result := fGameTickCount/24/60/60/10;
end;


function TKMGame.GetPeacetimeRemaining: TDateTime;
begin
  Result := Max(0, Int64(fGameOptions.Peacetime*600)-fGameTickCount)/24/60/60/10;
end;


//Tests whether time has past
function TKMGame.CheckTime(aTimeTicks: Cardinal): Boolean;
begin
  Result := (fGameTickCount >= aTimeTicks);
end;


//We often need to see if game is MP
function TKMGame.IsMultiplayer: Boolean;
begin
  Result := fGameMode = gmMulti;
end;


function TKMGame.IsReplay: Boolean;
begin
  Result := fGameMode = gmReplay;
end;


procedure TKMGame.ShowMessage(aKind: TKMMessageKind; aText: string; aLoc: TKMPoint);
begin
  fGamePlayInterface.MessageIssue(aKind, aText, aLoc);
end;


function TKMGame.IsPeaceTime:boolean;
begin
  Result := not CheckTime(fGameOptions.Peacetime * 600);
end;


//Compute cursor position and store it in global variables
procedure TKMGame.UpdateGameCursor(X, Y: Integer; Shift: TShiftState);
begin
  with GameCursor do
  begin
    Float.X := fViewport.Position.X + (X-fViewport.ViewRect.Right/2-TOOLBAR_WIDTH/2)/CELL_SIZE_PX/fViewport.Zoom;
    Float.Y := fViewport.Position.Y + (Y-fViewport.ViewRect.Bottom/2)/CELL_SIZE_PX/fViewport.Zoom;
    Float.Y := fTerrain.ConvertCursorToMapCoord(Float.X,Float.Y);

    //Cursor cannot reach row MapY or column MapX, they're not part of the map (only used for vertex height)
    Cell.X := EnsureRange(round(Float.X+0.5), 1, fTerrain.MapX-1); //Cell below cursor in map bounds
    Cell.Y := EnsureRange(round(Float.Y+0.5), 1, fTerrain.MapY-1);

    SState := Shift;
  end;
end;


procedure TKMGame.UpdatePeaceTime;
var
  PeaceTicksRemaining: Cardinal;
begin
  PeaceTicksRemaining := Max(0, Int64((fGameOptions.Peacetime * 600)) - fGameTickCount);
  if (PeaceTicksRemaining = 1) and (fGameMode = gmMulti) then
  begin
    fNetworking.PostLocalMessage(fTextLibrary[TX_MP_PEACETIME_OVER], false);
    fSoundLib.Play(sfxn_Peacetime, 1.0, True); //Fades music
  end;
end;


function TKMGame.GetNewID:cardinal;
begin
  Inc(fIDTracker);
  Result := fIDTracker;
end;


procedure TKMGame.SetGameSpeed(aSpeed: Word);
begin
  Assert(aSpeed > 0);

  //Make the speed toggle between 1 and desired value
  if aSpeed = fGameSpeed then
    fGameSpeed := 1
  else
    fGameSpeed := aSpeed;

  if fGameSpeed > 5 then
  begin
    fGameSpeedMultiplier := Round(fGameSpeed / 4);
    fTimerGame.Interval := Round(fGameApp.GlobalSettings.SpeedPace / fGameSpeed * fGameSpeedMultiplier);
  end
  else
  begin
    fGameSpeedMultiplier := 1;
    fTimerGame.Interval := Round(fGameApp.GlobalSettings.SpeedPace / fGameSpeed);
  end;

  if fGamePlayInterface <> nil then
    fGamePlayInterface.ShowClock(fGameSpeed);
end;


//In replay mode we can step the game by exactly one frame and then pause again
procedure TKMGame.StepOneFrame;
begin
  Assert(fGameMode = gmReplay, 'We can work step-by-step only in Replay');
  SetGameSpeed(1); //Make sure we step only one tick. Do not allow multiple updates in UpdateState loop
  fAdvanceFrame := True;
end;


//Saves the game in all its glory
//Base savegame gets copied from save99.bas
//Saves command log to RPL file
procedure TKMGame.Save(const aFileName: string);
var
  SaveStream: TKMemoryStream;
  fGameInfo: TKMGameInfo;
  i, NetIndex: integer;
  s: string;
begin
  fLog.AppendLog('Saving game');

  if (fGameMode in [gmMapEd, gmReplay]) then
  begin
    Assert(false, 'Saving from wrong state?');
    Exit;
  end;

  SaveStream := TKMemoryStream.Create;

  fGameInfo := TKMGameInfo.Create;
  fGameInfo.Title := fGameName;
  fGameInfo.TickCount := fGameTickCount;
  fGameInfo.MissionMode := fMissionMode;
  fGameInfo.MapSizeX := fTerrain.MapX;
  fGameInfo.MapSizeY := fTerrain.MapY;
  fGameInfo.VictoryCondition := 'Win';
  fGameInfo.DefeatCondition := 'Lose';
  fGameInfo.PlayerCount := fPlayers.Count;
  for i:=0 to fPlayers.Count-1 do
  begin
    if fNetworking <> nil then
      NetIndex := fNetworking.NetPlayers.PlayerIndexToLocal(i)
    else
      NetIndex := -1;

    if NetIndex = -1 then begin
      fGameInfo.LocationName[i] := 'Unknown';
      fGameInfo.PlayerTypes[i] := pt_Human;
      fGameInfo.ColorID[i] := 0;
      fGameInfo.Team[i] := 0;
    end else begin
      fGameInfo.LocationName[i] := fNetworking.NetPlayers[NetIndex].Nikname;
      fGameInfo.PlayerTypes[i] := fNetworking.NetPlayers[NetIndex].GetPlayerType;
      fGameInfo.ColorID[i] := fNetworking.NetPlayers[NetIndex].FlagColorID;
      fGameInfo.Team[i] := fNetworking.NetPlayers[NetIndex].Team;
    end
  end;

  fGameInfo.Save(SaveStream);
  fGameInfo.Free;
  fGameOptions.Save(SaveStream);

  //Because some stuff is only saved in singleplayer we need to know whether it is included in this save,
  //so we can load multiplayer saves in single player and vice versa.
  SaveStream.Write(fGameMode = gmMulti);

  if fGameMode <> gmMulti then
    fGamePlayInterface.SaveMapview(SaveStream); //Minimap is near the start so it can be accessed quickly

  SaveStream.Write(fCampaignName); //When we load that save we will need to know which campaign to display after victory
  SaveStream.Write(fCampaignMap); //When we load that save we will need to know which campaign to display after victory

  SaveStream.Write(fIDTracker); //Units-Houses ID tracker
  SaveStream.Write(GetKaMSeed); //Include the random seed in the save file to ensure consistency in replays

  if fGameMode <> gmMulti then
    SaveStream.Write(PlayOnState, SizeOf(PlayOnState));

  fTerrain.Save(SaveStream); //Saves the map
  fPlayers.Save(SaveStream, fGameMode = gmMulti); //Saves all players properties individually
  fProjectiles.Save(SaveStream);
  fEventsManager.Save(SaveStream);

  //Relative path to strings will be the same for all MP players
  s := ExtractRelativePath(ExeDir, ChangeFileExt(fMissionFile, '.%s.libx'));
  SaveStream.Write(s);

  //Parameters that are not identical for all players should not be saved as we need saves to be
  //created identically on all player's computers. Eventually these things can go through the GIP

  //For multiplayer consistency we compare all saves CRCs, they should be created identical on all player's computers.
  if fGameMode <> gmMulti then
  begin
    //Viewport settings are unique for each player
    fViewport.Save(SaveStream);
    fGamePlayInterface.Save(SaveStream); //Saves message queue and school/barracks selected units
    //Don't include fGameSettings.Save it's not required for settings are Game-global, not mission
  end;

  //If we want stuff like the MessageStack and screen center to be stored in multiplayer saves,
  //we must send those "commands" through the GIP so all players know about them and they're in sync.
  //There is a comment in fGame.Load about MessageList on this topic.

  //Makes the folders incase they were deleted
  s := SaveName(aFileName,'sav', fGameMode = gmMulti);
  ForceDirectories(ExtractFilePath(s));
  SaveStream.SaveToFile(SaveName(aFileName,'sav', fGameMode = gmMulti)); //Some 70ms for TPR7 map
  SaveStream.Free;

  fLog.AppendLog('Save done');

  CopyFile(PChar(SaveName('basesave','bas', fGameMode = gmMulti)), PChar(SaveName(aFileName,'bas', fGameMode = gmMulti)), false); //replace Replay base savegame
  fGameInputProcess.SaveToFile(SaveName(aFileName,'rpl', fGameMode = gmMulti)); //Adds command queue to savegame

  fLog.AppendLog('Saving game', true);
end;


procedure TKMGame.Load(const aFileName: string; aReplay: Boolean = False);
var
  LoadStream: TKMemoryStream;
  GameInfo: TKMGameInfo;
  LoadFileExt: string;
  LibxPath: AnsiString;
  LoadedSeed: Longint;
  SaveIsMultiplayer: Boolean;
begin
  fLog.AppendLog('Loading game: ' + aFileName);
  if aReplay then
    LoadFileExt := 'bas'
  else
    LoadFileExt := 'sav';

  LoadStream := TKMemoryStream.Create;
  GameInfo := TKMGameInfo.Create;

  if not FileExists(SaveName(aFileName, LoadFileExt, fGameMode = gmMulti)) then
    raise Exception.Create('Savegame could not be found');

  LoadStream.LoadFromFile(SaveName(aFileName, LoadFileExt, fGameMode = gmMulti));

  //We need only few essential parts from GameInfo, the rest is duplicate from fTerrain and fPlayers

  GameInfo.Load(LoadStream);
  fGameName := GameInfo.Title;
  fGameTickCount := GameInfo.TickCount;
  fMissionMode := GameInfo.MissionMode;
  FreeAndNil(GameInfo);
  fGameOptions.Load(LoadStream);

  //So we can allow loading of multiplayer saves in single player and vice versa we need to know which type THIS save is
  LoadStream.Read(SaveIsMultiplayer);

  if not SaveIsMultiplayer then
    fGamePlayInterface.LoadMapview(LoadStream); //Not used, (only stored for preview) but it's easiest way to skip past it

  LoadStream.Read(fCampaignName); //When we load that save we will need to know which campaign to display after victory
  LoadStream.Read(fCampaignMap); //When we load that save we will need to know which campaign to display after victory

  LoadStream.Read(fIDTracker);
  LoadStream.Read(LoadedSeed);

  if not SaveIsMultiplayer then
    LoadStream.Read(PlayOnState, SizeOf(PlayOnState));

  //Load the data into the game
  fTerrain.Load(LoadStream);

  fPlayers := TKMPlayersCollection.Create;
  fPlayers.Load(LoadStream);
  fProjectiles.Load(LoadStream);
  fEventsManager.Load(LoadStream);

  //Load LIBX strings used in a mission by their relative path to ExeDir
  //Relative path should be the same across all MP players,
  //locale info shuold not be a problem as it is represented by %s
  LoadStream.Read(LibxPath);
  fTextLibrary.LoadMissionStrings(ExeDir + LibxPath);

  //Multiplayer saves don't have this piece of information. Its valid only for MyPlayer
  //todo: Send all message commands through GIP
  if not SaveIsMultiplayer then
  begin
    fViewport.Load(LoadStream);
    fGamePlayInterface.Load(LoadStream);
  end;

  FreeAndNil(LoadStream);

  if (fGameMode = gmMulti) and not aReplay then
    fGameInputProcess := TGameInputProcess_Multi.Create(gipRecording, fNetworking)
  else
    fGameInputProcess := TGameInputProcess_Single.Create(gipRecording);
  fGameInputProcess.LoadFromFile(SaveName(aFileName, 'rpl', fGameMode = gmMulti));

  if not aReplay then
    CopyFile(PChar(SaveName(aFileName,'bas', fGameMode = gmMulti)), PChar(SaveName('basesave','bas', fGameMode = gmMulti)), false); //replace Replay base savegame

  fPlayers.SyncLoad; //Should parse all Unit-House ID references and replace them with actual pointers
  fTerrain.SyncLoad; //IsUnit values should be replaced with actual pointers

  if fGameMode = gmMulti then
    MultiplayerRig;

  //When everything is ready we can update UI
  UpdateUI;

  SetKaMSeed(LoadedSeed);

  fLog.AppendLog('Loading game', True);
end;


procedure TKMGame.UpdateGame(Sender: TObject);
var I: Integer; T: Cardinal;
begin
  if fIsPaused then Exit;

  case fGameMode of
    gmSingle, gmMulti:
                  if not (fGameMode = gmMulti) or (fNetworking.NetGameState <> lgs_Loading) then
                  for I := 1 to fGameSpeedMultiplier do
                  begin
                    if fGameInputProcess.CommandsConfirmed(fGameTickCount+1) then
                    begin
                      T := TimeGet;

                      if fWaitingForNetwork then GameWaitingForNetwork(false); //No longer waiting for players
                      inc(fGameTickCount); //Thats our tick counter for gameplay events
                      if (fGameMode = gmMulti) then fNetworking.LastProcessedTick := fGameTickCount;
                      //Tell the master server about our game on the specific tick (host only)
                      if (fGameMode = gmMulti) and fNetworking.IsHost and (
                         ((fMissionMode = mm_Normal) and (fGameTickCount = ANNOUNCE_BUILD_MAP)) or
                         ((fMissionMode = mm_Tactic) and (fGameTickCount = ANNOUNCE_BATTLE_MAP))) then
                        fNetworking.ServerQuery.SendMapInfo(fGameName, fNetworking.NetPlayers.GetConnectedCount);

                      fEventsManager.ProcTime(fGameTickCount);
                      UpdatePeacetime; //Send warning messages about peacetime if required
                      fTerrain.UpdateState;
                      fPlayers.UpdateState(fGameTickCount); //Quite slow
                      if fIsEnded then Exit; //Quit the update if game was stopped by MyPlayer defeat
                      fProjectiles.UpdateState; //If game has stopped it's NIL

                      fGameInputProcess.RunningTimer(fGameTickCount); //GIP_Multi issues all commands for this tick
                      //In aggressive mode store a command every tick so we can find exactly when a replay mismatch occurs
                      if AGGRESSIVE_REPLAYS then
                        fGameInputProcess.CmdTemp(gic_TempDoNothing);

                      //Each 1min of gameplay time
                      //Don't autosave if the game was put on hold during this tick
                      if (fGameTickCount mod 600 = 0) and fGameApp.GlobalSettings.Autosave then
                        AutoSave;

                      fPerfLog.AddTime(TimeGet - T);

                      //Break the for loop (if we are using speed up)
                      if DoGameHold then break;
                    end
                    else
                    begin
                      fGameInputProcess.WaitingForConfirmation(fGameTickCount);
                      if TGameInputProcess_Multi(fGameInputProcess).GetNumberConsecutiveWaits > 5 then
                        GameWaitingForNetwork(true);
                    end;
                    fGameInputProcess.UpdateState(fGameTickCount); //Do maintenance
                  end;
    gmReplay:     for I := 1 to fGameSpeedMultiplier do
                  begin
                    Inc(fGameTickCount); //Thats our tick counter for gameplay events
                    fTerrain.UpdateState;
                    fPlayers.UpdateState(fGameTickCount); //Quite slow
                    if fIsEnded then exit; //Quit the update if game was stopped by MyPlayer defeat
                    fProjectiles.UpdateState; //If game has stopped it's NIL

                    //Issue stored commands
                    fGameInputProcess.ReplayTimer(fGameTickCount);
                    if fIsEnded then Exit; //Quit if the game was stopped by a replay mismatch
                    if not SkipReplayEndCheck and fGameInputProcess.ReplayEnded then
                      RequestGameHold(gr_ReplayEnd);

                    if fAdvanceFrame then begin
                      fAdvanceFrame := False;
                      fIsPaused := True;
                    end;

                    //Break the for loop (if we are using speed up)
                    if DoGameHold then break;
                  end;
    gmMapEd:   begin
                  fTerrain.IncAnimStep;
                  fPlayers.IncAnimStep;
                end;
  end;

  if DoGameHold then GameHold(true,DoGameHoldState);
end;


procedure TKMGame.UpdateState(aGlobalTickCount: Cardinal);
begin
  if not fIsPaused then
    fActiveInterface.UpdateState(aGlobalTickCount);
end;


//This is our real-time "thread", use it wisely
procedure TKMGame.UpdateStateIdle(aFrameTime: Cardinal);
begin
  if not fIsPaused then
    fViewport.UpdateStateIdle(aFrameTime); //Check to see if we need to scroll

  //Terrain should be updated in real time when user applies brushes
  if fGameMode = gmMapEd then
    fTerrain.UpdateStateIdle;
end;


procedure TKMGame.UpdateUI;
begin
  if fGameMode = gmMapEd then
  begin
    fViewport.ResizeMap(fTerrain.MapX, fTerrain.MapY);
    fViewport.ResetZoom;

    fMapEditorInterface.Player_UpdateColors;
    fMapEditorInterface.UpdateMapName(fGameName);
    fMapEditorInterface.UpdateMapSize(fTerrain.MapX, fTerrain.MapY);
  end
  else
  begin
    fViewport.ResizeMap(fTerrain.MapX, fTerrain.MapY);
    fViewport.Position := KMPointF(MyPlayer.CenterScreen);
    fViewport.ResetZoom; //This ensures the viewport is centered on the map

    fGamePlayInterface.UpdateMapSize(fTerrain.MapX, fTerrain.MapY);
    fGamePlayInterface.UpdateMenuState(fMissionMode = mm_Tactic, False);
  end;
end;

function TKMGame.SaveName(const aName, aExt: string; aMultiPlayer: Boolean): string;
begin
  if aMultiPlayer then
    Result := ExeDir + 'SavesMP\' + aName + '.' + aExt
  else
    Result := ExeDir + 'Saves\' + aName + '.' + aExt;
end;


end.
