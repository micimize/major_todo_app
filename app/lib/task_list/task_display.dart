import 'package:flutter/material.dart';
import 'package:todo_app/schema.graphql.dart' hide document;
import 'package:todo_app/stopwatch/stopwatch.dart';
import 'package:major_graphql_flutter/typed_mutation.dart';
import 'package:todo_app/task_list/update_task.graphql.dart' as update;

final UpdateTaskMutation = TypedMutation.factoryFor<update.UpdateTaskResult,
    update.UpdateTaskVariables>(
  documentNode: update.document,
  dataFromJson: update.UpdateTaskResult.fromJson,
);

class TaskDisplay extends StatelessWidget {
  const TaskDisplay({
    Key key,
    @required this.task,
  }) : super(key: key);

  final Task task;

  @override
  Widget build(BuildContext context) => UpdateTaskMutation(
        builder: ({
          runMutation,
          data,
          loading,
          exception,
        }) {
          return ListTile(
            leading: IconButton(
              onPressed: task.isCompleted
                  ? null
                  : () => runMutation(
                        update.UpdateTaskVariables(
                          (b) => b
                            ..taskId = task.id
                            ..taskPatch = (TaskPatchBuilder()
                              ..closed = DateTime.now().toUtc()
                              ..lifecycle = TaskLifecycle.COMPLETED),
                        ),
                      ),
              icon: Icon(
                task.isCompleted
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
              ),
            ),
            title: Text(task.title),
            subtitle: Text(task.description ?? ''),
            trailing: DisplayStopwatch(
              value: task.stopwatchValue,
              placeholder: 'todo',
              onChanged: (value) => runMutation(
                update.UpdateTaskVariables(
                  (b) => b
                    ..taskId = task.id
                    ..taskPatch = (TaskPatchBuilder()
                      ..stopwatchValue = value.toBuilder()),
                ),
              ),
            ),
          );
        },
      );
}

extension _Helpers on Task {
  bool get isCompleted => lifecycle == TaskLifecycle.COMPLETED;
}
