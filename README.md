# todo_app

An app that helps you get things done

## Roadmap

This is just a loose feature roadmap right now,
Soon we'll want a real release/lifecycel roadmap

### Road to 0.1.0: The "Janktown" MVP
- [X] Basic ad-hoc tasks (creation / completion)
- [X] Task Stopwatch
- [X] Hide completed items after X hours 
- [X] History page (wit details like duration, created)
    - [X] bottom nav + new page
    - [X] an "all tasks" query 
    - [X] listing tasks

### 0.2.0: Deployment
- [ ] Complete Google sign-in integration
  - [X] Tables
  - [X] jwt validation
  - [X] login screen
  - [ ] https://github.com/micimize/major/issues/10
- [ ] Set up testflight / CI

### 0.2.5: Design
- [ ] Basic design work (sketch)
- [ ] Implement Designs

### 0.3.0
- [ ] Visualizations / "serious" Quantification
- [ ] Task "Ongoing / Partially complete" concept
      (richer bullet journal carryover) 
- [ ] Task Notes
- [ ] Import/Export format
- [ ] CLI? Web version?
- [ ] copy / paste? possibly task templates? 
- [ ] structured tasks / grouped tasks:
      considerations: do tasks complete along with their constituent parts?
      should the be implemented recursively? Or a seperate concept



ios/Runner/GoogleService-Info.plist needs to be added

### Structure

```bash
tree -L 3 -d -I 'node_modules|ios|android|build' .
.
├── act # scripts for ops stuff like testing actions and instantiating the db
├── app # the flutter app
│   ├── lib
│   │   ├── history  # submodules likely not current
│   │   ├── stopwatch
│   │   └── task_list
│   └── test
└── backend # postgraphile backend adapted from graphile/starter
    ├── @app
    │   ├── __tests__
    │   ├── config # shared configuration handling
    │   ├── db     # graphile-migrate based schema authoring
    │   ├── server # graphile server + firebase auth handling
    │   └── worker # disabled background worker (graphile-worker)
    └── data # output dir for schema info.
```


### notes
* app/ios/Runner/GoogleService-Info.plist is required but contains an api key


