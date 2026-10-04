# Platform rules — AutoCAD add-in (AutoCAD .NET API R24 = AutoCAD 2024, .NET Framework 4.8)

Project rules (`AGENTS.md`, `CLAUDE.md`, `docs/rules/**`) override this file where they differ.

Lower layers for AutoCAD:
- **L1 CAD Services** — generic operations: entity query/selection, create/modify entities, blocks &
  attributes, layers/styles, XData/XRecord/Extension dictionaries, sheet sets, transaction runner, jig/prompt helpers.
- **L0 Acad Core** — extension methods/helpers on `Database`, `Transaction`, `Editor`, `Entity`,
  geometry (`Point3d`, `Vector3d`, `Matrix3d`), shareable between add-ins.

Rules
1. **Version lock:** AutoCAD 2024 = AutoCAD.NET 24.x (R24), .NET Framework 4.8, C# 7.3 in legacy csproj.
   AutoCAD 2025+ is .NET 8 — never add 25.x packages or 2025 interop DLLs to a 2024 project.
2. Database access only inside
   `using (var tr = db.TransactionManager.StartTransaction()) { ...; tr.Commit(); }`.
   Open with `tr.GetObject(id, OpenMode.ForRead)`; `UpgradeOpen()` only when writing.
   One transaction per user action, not per entity.
3. New entities: `btr.AppendEntity(ent); tr.AddNewlyCreatedDBObject(ent, true);`.
   A `DBObject` created with `new` but never added to the database must be disposed.
4. Store `ObjectId` within a session and `Handle` for persistence; never keep `DBObject`s after the transaction ends.
5. Threading & context: API only on AutoCAD's main thread. From modeless UI (PaletteSet, WPF window) or
   application-context code, wrap writes in `using (doc.LockDocument())`, or run via
   `DocumentManager.ExecuteInCommandContextAsync` / a registered command. Never from `Task.Run`/timers.
6. Commands: `[CommandMethod("HW_...")]`, thin (compose + call use case). Check every
   `PromptResult.Status` (`PromptStatus.OK`, cancel → return quietly).
7. `IExtensionApplication.Initialize` stays light and is wrapped in try/catch
   (an exception there silently prevents the plug-in from loading). Defer ribbon creation until the ribbon exists.
8. Selection: `Editor.GetSelection` / `SelectAll` with a `SelectionFilter` (`TypedValue(DxfCode.Start, "LINE")`, layer...)
   instead of iterating model space and filtering in LINQ.
9. Coordinates: know WCS vs UCS (`ed.CurrentUserCoordinateSystem`); compare with `Tolerance.Global` / `IsEqualTo`.
10. XData: register the app name in `RegAppTable` before writing; prefer Extension dictionaries/XRecords for large data.
11. COM interop (`Autodesk.AutoCAD.Interop`, `AcSmComponents` sheet sets): main thread only; release COM objects
    (`Marshal.ReleaseComObject`) and always unlock sheet-set databases in `finally`.
12. `AcMgd`, `AcDbMgd`, `AcCoreMgd`, `AcWindows`, `AdWindows`: Copy Local = False / `ExcludeAssets="runtime"`.
13. AutoCAD can't unload .NET assemblies: build to a separate output (build gate does), restart AutoCAD or
    NETLOAD a fresh copy for manual tests. Manual test steps must say which DWG to open and which command to run.
14. **Version floor:** the lowest AutoCAD year the DLL is deployed to; forbid APIs newer than that year.
15. Idempotency: re-running a command must not duplicate entities/blocks/layouts unless the ticket says so;
    bulk erase/overwrite needs explicit user confirmation.
16. **Testability:** `Point3d`/`Matrix3d` need AcDbMgd loaded — keep math on doubles/own structs in Domain so level-A
    unit tests run without AutoCAD; host-dependent cases are level B (DWG name, command, inputs, expected values
    with unit/tolerance, evidence to capture).
