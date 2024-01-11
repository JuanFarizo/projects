import { useReducer } from 'react';

type CounterState = {
  count: number;
};
type Action = {
  type: string;
  payload: number;
};

const initializeState = { count: 0 };

function reducer(state: CounterState, action: Action) {
  switch (action.type) {
    case 'increment':
      return { count: state.count + action.payload };
    case 'decrement':
      return { count: state.count - action.payload };
    default:
      return state;
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
    </>
  );
}

export default Counter;
