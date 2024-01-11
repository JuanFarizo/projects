import { Component } from 'react';

//1. Have to define the props and state type
type CounterProps = {
  message: string;
};
type CounterState = {
  count: number;
};

//2. Use the type in the Component <>
export class CounterClass extends Component<CounterProps, CounterState> {
  state = {
    count: 0,
  };
  handleClick = () => {
    this.setState((prevState) => ({ count: prevState.count + 1 }));
  };
  render() {
    return (
      <div>
        <button type="button" onClick={this.handleClick}>
          Increment
        </button>
        {this.props.message} {this.state.count}
      </div>
    );
  }
}
