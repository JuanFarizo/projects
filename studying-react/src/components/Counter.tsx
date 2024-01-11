import { useReducer } from 'react';

type CounterState = {
  count: number;
};

type IncrementAction = {
  type: 'increment' | 'decrement';
  payload: number;
};

type ResetAction = {
  type: 'reset';
};

type Action = IncrementAction | ResetAction;

const initializeState = { count: 0 };

function reducer(state: CounterState, action: Action) {
  switch (action.type) {
    case 'increment':
      return { count: state.count + action.payload };
    case 'decrement':
      return { count: state.count - action.payload };
    case 'reset':
      return initializeState;
  }
}

function Counter() {
  const [state, dispatch] = useReducer(reducer, initializeState);
  return (
    <>
      <h3>Counter: {state.count}</h3>
      <button
        type="button"
        onClick={() => dispatch({ type: 'increment', payload: 10 })}
      >
        Increment 10
      </button>
      <button
        type="button"
        onClick={() => dispatch({ type: 'decrement', payload: 10 })}
      >
        Decrement 10
      </button>
      <button type="button" onClick={() => dispatch({ type: 'reset' })}>
        Reset
      </button>
    </>
  );
}

export default Counter;
