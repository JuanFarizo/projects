interface Props {
  inputValue: string;
  handleOnChange: (event: React.ChangeEvent<HTMLInputElement>) => void;
}

function Input({ inputValue, handleOnChange }: Props) {
  return <input type="text" onChange={handleOnChange} />;
}

export default Input;
