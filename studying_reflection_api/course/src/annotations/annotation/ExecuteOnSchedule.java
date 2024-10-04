package annotations.annotation;

import java.lang.annotation.Repeatable;

@Repeatable(ExecutionSchedule.class)
public @interface ExecuteOnSchedule {
    int delaySeconds() default 0;

    int periodSeconds();
}
