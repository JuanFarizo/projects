import React from 'react';
import ListGroup from '../ListGroup';

//prettier-ignore
export const CustomComponent = (props: React.ComponentProps<typeof ListGroup>) => {
  return <div>{props.items}</div>;
};
