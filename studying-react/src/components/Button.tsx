import React, { useState } from 'react';

interface Props {
  description: string;
  handleOnClick: (event: React.MouseEvent<HTMLButtonElement>) => void;
}
let counter = 0;

/* const handleClickedButton = () => {
  const colors = ['primary', 'secondary', 'success'];
  let index = counter % 3;
  console.log('index', index);
  counter++;
  return colors[index];
}; */

const Button = ({ description, handleOnClick }: Props) => {
  const [color, setColor] = useState('primary');
  return (
    <div>
      <button
        type="button"
        className={'btn btn-' + color}
        onClick={handleOnClick}
      >
        {description}
      </button>
    </div>
  );
};

export default Button;
