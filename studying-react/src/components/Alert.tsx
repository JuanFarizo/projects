import { ReactNode } from 'react';

interface Props {
  children?: ReactNode;
  onClose: () => void;
}

type StringLiteral = {
  message: 'loading' | 'success' | 'pending'; // This can be one of the three options
};

const Alert = ({ children, onClose }: Props) => {
  return (
    <>
      <div
        className="alert alert-warning alert-dismissible fade show"
        role="alert"
      >
        {children}
        <strong>Rayos y centellas!</strong> You should check in on some of those
        fields below.
        <button
          type="button"
          className="btn-close"
          data-bs-dismiss="alert"
          aria-label="Close"
          onClick={onClose}
        ></button>
      </div>
    </>
  );
};

export default Alert;
