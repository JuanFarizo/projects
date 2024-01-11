type RandomNumberType = {
  value: number;
};
type PositiveNumber = RandomNumberType & {
  isPositive: boolean;
  isNegative?: never;
  isZero?: never;
};

type NegativeNumber = RandomNumberType & {
  isNegative: boolean;
  isZero?: never;
  isPositive?: never;
};
type ZeroNumber = RandomNumberType & {
  isZero: boolean;
  isPositive?: never;
  isNegative?: never;
};

type RandomNumberProps = PositiveNumber | NegativeNumber | ZeroNumber;

export const RandomNumber = ({
  value,
  isPositive,
  isNegative,
  isZero,
}: RandomNumberProps) => {
  return (
    <div>
      {value} {isPositive && 'Is Positive'} {isNegative && 'Is Negative'}{' '}
      {isZero && 'Is Zero'}
    </div>
  );
};
