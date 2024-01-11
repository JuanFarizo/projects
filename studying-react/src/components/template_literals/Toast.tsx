import React from 'react';

// Position prop can be on of:
// "left-center" | "left-top" | "left-bottom" | "center" | "center-top"
// "center-bottom" | "right-center" | "right-top" | "right-bottom"

type HorizontalPosition = 'left' | 'right' | 'center';
type VerticalPosition = 'top' | 'center' | 'bottom';

type ToastProps = {
  //prettier-ignore
  position: Exclude<`${HorizontalPosition}-${VerticalPosition}`, 'center-center'> | 'center'; // Typescript is going to inferer all the posible
  // positions. Can exclude some properties like center-center
};

export const Toast = ({ position }: ToastProps) => {
  return <div>Toast Notification Position - {position}</div>;
};
