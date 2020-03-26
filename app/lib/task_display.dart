import 'package:flutter/material.dart';
import 'package:todo_app/schema.graphql.dart' hide document;
import 'package:todo_app/pointless_helpers.dart';
import 'package:todo_app/task_stopwatch.dart';
import 'package:todo_app/typed_mutation.dart';
import 'package:todo_app/update_task.graphql.dart' as update;

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
              onPressed: () => runMutation(
                update.UpdateTaskVariables(
                  (b) => b
                    ..taskId = task.id
                    ..taskPatch = (TaskPatchBuilder()
                      ..lifecycle = TaskLifecycle.COMPLETED),
                ),
              ),
              icon: Icon(
                task.isCompleted
                    ? Icons.check_box
                    : Icons.check_box_outline_blank,
              ),
            ),
            title: Row(
              children: [
                Expanded(child: Text(task.title)),
                SizedBox(width: 12),
                Text(
                  task.stopwatchValue?.display() ?? ' todo',
                  style: Theme.of(context).textTheme.caption,
                )
              ],
            ),
            subtitle: Text(task.description ?? ''),
            trailing: TaskStopwatch(
              value: task.stopwatchValue,
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
