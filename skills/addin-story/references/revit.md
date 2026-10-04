# Platform rules — Revit add-in (Revit API, .NET Framework 4.8, Revit ≤ 2024)

Project rules (`AGENTS.md`, `CLAUDE.md`, `docs/rules/**`) override this file where they differ.

Lower layers for Revit:
- **L1 Revit Services** — generic operations: element query, parameter read/write, create/modify,
  tags & annotation, transaction runner, selection, geometry extraction.
- **L0 Revit Core** — extension methods/helpers on the Revit API (collectors, parameters, units,
  geometry, ElementId), shareable between add-ins.

Rules
1. **Thread/context:** API calls only from a valid API context (`IExternalCommand.Execute`, modal dialog,
   Revit events, `IExternalEventHandler.Execute`). Never from `Task.Run`, timers, WPF modeless windows,
   named-pipe / MCP / HTTP handlers. Those go through the project's dispatcher (e.g. an `ExternalEvent`
   queue or a `Dispatcher.Run(func, timeout)` helper) — grep for it before writing a new one.
2. Modifications only inside `using (var t = new Transaction(doc, "Readable undo name")) { t.Start(); ... t.Commit(); }`.
   One transaction per user action, not per element. `TransactionGroup` + `Assimilate()` for multi-step actions.
   No `doc.Regenerate()` and no `FilteredElementCollector` inside per-element loops.
3. Ids: `ElementId` only within a session; **`UniqueId` for anything persisted** (JSON, settings, ExtensibleStorage
   references, files, external systems). Never keep `Element` objects across transactions/documents.
4. `FilteredElementCollector`: quick filters first (`OfClass`, `OfCategory`, `WhereElementIsNotElementType`,
   view scope), slow filters / LINQ last. Never an unfiltered collector.
5. Units: internal feet/radians; convert at the boundary with `UnitUtils` (`ForgeTypeId`, 2021+).
   Expected values in tests state the unit and a tolerance.
6. **Version floor:** the lowest Revit year the DLL is *deployed* to, not the year it compiles against.
   If one build ships to 2022–2025, forbid APIs newer than 2022: `ElementId.Value`, `new ElementId(long)`,
   APIs removed/renamed between floor and compile year. Revit 2025+ is .NET 8 — never mix into a net48 project.
7. Worksharing: check element ownership before editing workshared models. Check `doc.IsReadOnly` / `IsModifiable`.
8. Idempotency: running a create command twice must not duplicate elements/views/sheets (find-or-create by a
   stable key) unless the ticket says otherwise. Bulk delete/overwrite needs explicit user confirmation.
9. `IExternalCommand.Execute`: try/catch → `Result.Failed` + message; `OperationCanceledException` → `Result.Cancelled`.
   Only Commands/UI show `TaskDialog`. Log through the project logger, never swallow exceptions.
10. Dispose `Transaction`, `SubTransaction` and other `IDisposable` API objects.
11. `RevitAPI.dll` / `RevitAPIUI.dll` references: Copy Local = False. Legacy csproj lists files explicitly — a new
    `.cs` must be added to every twin project (e.g. `X.csproj` and `X_R2022.csproj`).
12. **Testability:** `XYZ`, `BoundingBoxXYZ`, `Transform`… cannot be constructed outside Revit. Keep math on
    doubles / own structs in Domain so level-A unit tests run without the host; host-dependent cases are level B.
13. Manual test (level B) = named model (golden/test `.rvt`), Revit year, ribbon tab/panel/button, inputs,
    expected values with unit/tolerance, evidence to capture. Restart Revit after build (or Add-In Manager).
