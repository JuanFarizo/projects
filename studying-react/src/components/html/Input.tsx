import React from 'react';

type ButtonProps = React.ComponentProps<'input'>;

export const Input = (props: ButtonProps) => {
  return <input {...props} />;
};
